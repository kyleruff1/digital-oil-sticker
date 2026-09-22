defmodule DigitalOilStickerWeb.LocalStore.Session do
  @moduledoc """
  The ONLY module that mutates the LocalStore protocol assigns. Holds the
  hydration state machine, the pending-write ledger, and the timeout arms.
  Personal data lives in `assigns.garage` for the socket lifetime only — it
  is never persisted, logged, or broadcast (INV-23/24).
  """
  import Phoenix.Component, only: [assign: 3]
  alias DigitalOilSticker.LocalStore.{Envelope, Migrations, Validation}
  alias DigitalOilStickerWeb.Skins

  @hydration_deadline_ms Application.compile_env(
                           :digital_oil_sticker,
                           :hydration_deadline_ms,
                           5_000
                         )
  @ack_timeout_ms Application.compile_env(:digital_oil_sticker, :ack_timeout_ms, 2_000)

  @doc """
  The vehicle every garage page is currently about.

  The user's explicit choice (`prefs.active_vehicle_id`, set by the switcher on
  the sticker page) wins when it names a vehicle that still exists and is not
  archived; otherwise the first non-archived vehicle. The fallback matters:
  deleting the active vehicle leaves the stored id dangling, and dangling must
  mean "fall back", never "no vehicle" — the user still has a garage.

  Lives here because three pages were each keeping a private copy of this
  rule, which is how the switcher's choice would end up honored on one page
  and ignored on another.
  """
  def active_vehicle(garage) do
    live = Enum.reject(garage.vehicles, &(&1["archived"] == true))
    chosen_id = garage.prefs && garage.prefs["active_vehicle_id"]

    Enum.find(live, &(&1["vehicle_id"] == chosen_id)) || List.first(live)
  end

  @doc """
  The most recent oil change for one vehicle. Ordered by `(performed_at,
  event_id)` descending — the id breaks same-day ties deterministically, so two
  changes logged for one date do not swap "most recent" between renders.
  """
  def last_oil_change(garage, vehicle_id) do
    garage.events
    |> Enum.filter(&(&1["vehicle_id"] == vehicle_id))
    |> Enum.sort_by(&{&1["performed_at"], &1["event_id"]}, :desc)
    |> List.first()
  end

  @empty_garage %{
    vehicles: [],
    events: [],
    readings: [],
    usage: [],
    reminders: [],
    prefs: nil,
    meta: nil
  }

  def init(socket) do
    socket =
      socket
      |> assign(:local_state, :hydrating)
      |> assign(:seq, 0)
      |> assign(:pending_writes, %{})
      |> assign(:quarantine, [])
      |> assign(:read_only, false)
      |> assign(:storage_mode, :unknown)
      |> assign(:persist_granted, nil)
      # Fire-once guard for the auto-invoke of "local_store:request_persist"
      # on the first meaningful write. Once we've asked the browser to keep
      # storage under pressure, we do not ask again from stage_mutation —
      # the persist_result handler records the outcome in :persist_granted
      # and the storage settings page still exposes a manual override.
      |> assign(:persist_requested, false)
      |> assign(:quota, nil)
      # Co-assign with :quota (never a distinct primary state): true when
      # reported usage / quota >= 0.8. Initialised false so every LiveView can
      # pass @quota_pressure to renderers unconditionally, exactly like
      # @conflict_notice. See handle_hydrate/2 for the compute site.
      |> assign(:quota_pressure, false)
      |> assign(:cap_error, nil)
      # Another tab wrote newer data (handle_conflict sets this true). The
      # layout renders a banner when it's truthy; initialising to false here
      # means every LiveView can pass it to Layouts.app unconditionally.
      |> assign(:conflict_notice, false)
      # Writes the browser refused. Rendered persistently and never cleared by
      # time or navigation: a record the user believes they saved, which was
      # not saved, is the failure INV-24.5 exists to prevent.
      |> assign(:unsaved_writes, [])
      |> assign(:garage, @empty_garage)
      # The sticker skin, derived from prefs on every hydrate and write.
      # Pre-hydration it is the default — the skeleton renders in Service Bay,
      # which is also what a hydrate failure honestly leaves on screen.
      |> assign(:skin, Skins.default())
      |> assign(:catalog_budget, DigitalOilSticker.Catalog.RateLimit.new())

    if Phoenix.LiveView.connected?(socket) do
      ref = make_ref()
      Process.send_after(self(), {:local_store_deadline, ref}, @hydration_deadline_ms)
      assign(socket, :hydration_deadline_ref, ref)
    else
      assign(socket, :hydration_deadline_ref, nil)
    end
  end

  def handle_hydrate(socket, params) do
    byte_size = :erlang.external_size(params)

    with {:ok, envelope} <- Envelope.decode(params),
         :ok <- check_version(envelope),
         {:ok, %{data: data, quarantine: quarantine}} <- Validation.validate(envelope, byte_size) do
      quota = quota(envelope.storage)

      socket
      |> cancel_deadline()
      |> assign(:seq, envelope.seq)
      |> assign(:quarantine, quarantine)
      |> assign(:storage_mode, storage_mode(envelope.storage))
      |> assign(:persist_granted, get_in(envelope.storage, ["persist_granted"]))
      |> assign(:quota, quota)
      # Co-assign: pressure is derived from the same estimate the "Space"
      # line renders, so both surfaces move together on every hydrate. Not a
      # :local_state branch — writes stay enabled per FR-13.
      |> assign(:quota_pressure, quota_pressured?(quota))
      |> then(fn socket ->
        garage = to_garage(data)

        socket
        |> assign(:garage, garage)
        |> assign(:skin, Skins.from_prefs(garage.prefs))
        |> assign(:local_state, resolve_state(garage, envelope.storage))
      end)
    else
      {:error, {:newer_than_server, _}} ->
        socket
        |> cancel_deadline()
        |> assign(:read_only, true)
        |> assign(:local_state, :loaded)

      {:error, {:cap_exceeded, cap}} ->
        # NOT :storage_unavailable. That state means "we cannot tell whether
        # anything is stored here", which would be a lie: we know exactly what
        # happened, because we are the ones who refused the payload. FR-10 is
        # explicit that a security control must never masquerade as data loss —
        # the records are still in the browser, untouched.
        socket
        |> cancel_deadline()
        |> assign(:cap_error, cap)
        |> assign(:local_state, :hydration_refused)

      {:error, _} ->
        socket
        |> cancel_deadline()
        |> assign(:local_state, :storage_unavailable)
    end
  end

  def handle_deadline(socket, ref) do
    if socket.assigns[:hydration_deadline_ref] == ref and socket.assigns.local_state == :hydrating do
      # No retry loop: the state is honest and stays until a hydrate arrives.
      assign(socket, :local_state, :storage_unavailable)
    else
      socket
    end
  end

  @doc """
  Stage a mutation: assign mutation_id and seq, record it pending, push
  `local_store:put`, and arm the ack timeout. The caller renders the record
  as SAVING until the ack clears it — never as committed.

  ## `:navigate_to`

  Pass the destination here instead of calling `push_navigate/2` yourself.
  Navigation then happens when the browser ACKNOWLEDGES the write, not when we
  ask for it. The conformance suite found why this matters: navigating
  optimistically remounts the LiveView, and the remounted process has no memory
  of the write, so a refused write could never be reported — the user saw a
  clean new page and believed the entry was stored.
  """
  def stage_mutation(socket, upserts, deletes, opts \\ [])

  def stage_mutation(socket, upserts, deletes, opts) when is_list(opts) do
    # Restored to the flat wire shape at this single choke point. Hydration
    # nests keys this release does not know under "__unknown__"; persisting a
    # record in that nested form would permanently shadow fields a NEWER
    # release wrote flat — the exact forward-compatibility the schema's
    # carry-through exists to provide, silently broken on every write.
    upserts = Enum.map(upserts, &restore_record/1)

    mutation_id = generate_id()
    seq = socket.assigns.seq + 1

    payload =
      Envelope.build_put(mutation_id, seq, to_pairs(upserts, "record"), to_pairs(deletes, "key"))

    pending =
      Map.put(socket.assigns.pending_writes, mutation_id, %{
        seq: seq,
        status: :saving,
        upserts: upserts,
        deletes: deletes,
        navigate_to: Keyword.get(opts, :navigate_to)
      })

    Process.send_after(self(), {:local_store_ack_timeout, mutation_id}, @ack_timeout_ms)

    garage = socket.assigns.garage |> apply_upserts(upserts) |> apply_deletes(deletes)

    socket =
      socket
      |> assign(:pending_writes, pending)
      |> assign(:seq, seq)
      |> assign(:garage, garage)
      # Re-derived on every write, not only on skin writes: any prefs upsert
      # may carry (or drop) `sticker_skin`, and the attribute must track the
      # optimistically-applied garage, not the pre-write one.
      |> assign(:skin, Skins.from_prefs(garage.prefs))
      |> Phoenix.LiveView.push_event("local_store:put", payload)
      |> maybe_auto_request_persist()

    {socket, mutation_id}
  end

  # First real write into this browser is the moment to ask the UA to keep
  # storage under pressure — data the user meant to save exists, so a silent
  # eviction from now on would erase work rather than an empty shell. The
  # request only fires once per socket and only when we have not yet heard
  # back (persist_granted is nil); an explicit grant or refusal is respected,
  # and the manual button on the storage settings page still works as an
  # override. Guarded by :persist_requested so subsequent mutations stay
  # silent regardless of how many the user makes in a row.
  defp maybe_auto_request_persist(socket) do
    if socket.assigns.persist_requested == false and is_nil(socket.assigns.persist_granted) do
      socket
      |> assign(:persist_requested, true)
      |> Phoenix.LiveView.push_event("local_store:request_persist", %{})
    else
      socket
    end
  end

  def handle_ack(socket, %{"mutation_id" => id, "status" => "ok"}) do
    {write, pending} = Map.pop(socket.assigns.pending_writes, id)
    socket = assign(socket, :pending_writes, pending)

    case write do
      %{navigate_to: path} when is_binary(path) ->
        Phoenix.LiveView.push_navigate(socket, to: path)

      _ ->
        socket
    end
  end

  def handle_ack(socket, %{"mutation_id" => id, "reason" => reason}) do
    mark_unsaved(socket, id, reason)
  end

  def handle_ack(socket, %{"mutation_id" => id}) do
    mark_unsaved(socket, id)
  end

  def handle_ack(socket, _), do: socket

  def handle_ack_timeout(socket, mutation_id) do
    case socket.assigns.pending_writes[mutation_id] do
      %{status: :saving} -> mark_unsaved(socket, mutation_id)
      _ -> socket
    end
  end

  def handle_conflict(socket, _params) do
    # A newer write exists in this browser (another tab). Ask the client to
    # re-hydrate; show the reload notice.
    #
    # The deadline is RE-ARMED here. The first hydrate cancelled it, so
    # without a new one this :hydrating has no timeout escape — a dropped or
    # failed rehydrate left the tab a skeleton forever, with every mutation
    # disabled and only a manual reload out. Now it degrades to
    # :storage_unavailable like any other hydration that never arrives.
    ref = make_ref()
    Process.send_after(self(), {:local_store_deadline, ref}, @hydration_deadline_ms)

    socket
    |> assign(:local_state, :hydrating)
    |> assign(:conflict_notice, true)
    |> assign(:hydration_deadline_ref, ref)
    |> Phoenix.LiveView.push_event("local_store:rehydrate", %{})
  end

  def mutations_enabled?(socket) do
    socket.assigns.local_state in [:loaded, :empty] and not socket.assigns.read_only and
      socket.assigns.storage_mode != :session_only
  end

  @doc """
  Whether the prefs singleton failed validation and sits in quarantine.

  A caller about to write prefs must check this and skip the write: the
  staged record REPLACES the singleton wholesale, and replacing a quarantined
  record destroys content the validation contract promises to preserve (a
  newer release's settings, say) with no quarantine trace left to export.
  """
  def prefs_quarantined?(socket) do
    Enum.any?(socket.assigns.quarantine || [], &(&1.store == "prefs"))
  end

  # -- internals ---------------------------------------------------------------

  # Callers may pass either {store, payload} tuples or the wire-shaped
  # %{"store" => _, "record"/"key" => _} maps; Envelope.build_put/4 wants
  # tuples. Normalizing here keeps every call site from having to remember.
  defp to_pairs(list, value_key) do
    Enum.map(list, fn
      {store, value} when is_binary(store) -> {store, value}
      %{"store" => store} = m -> {store, Map.fetch!(m, value_key)}
    end)
  end

  defp restore_record(%{"store" => _, "record" => record} = upsert),
    do: %{upsert | "record" => DigitalOilSticker.LocalStore.Schema.V1.restore_unknown(record)}

  defp restore_record({store, record}),
    do: {store, DigitalOilSticker.LocalStore.Schema.V1.restore_unknown(record)}

  # A staged write is reflected in `garage` immediately, so a LiveView that
  # stays on the page after saving shows what the user just did instead of the
  # pre-save state. This is optimistic on purpose: the record still renders as
  # SAVING until the browser acks, and a failed ack surfaces as "Not saved to
  # this browser" rather than being silently rolled back (INV-24).
  defp apply_upserts(garage, upserts) do
    Enum.reduce(to_pairs(upserts, "record"), garage, fn {store, record}, acc ->
      case store_key(store) do
        {:list, field, id_key} ->
          Map.update!(acc, field, &upsert_by(&1, record, id_key))

        {:singleton, field} ->
          Map.put(acc, field, record)

        :unknown ->
          acc
      end
    end)
  end

  # Deletes mirror upserts: staged, then reflected immediately. Before this
  # existed, a deleted record stayed in `garage` — and therefore on screen —
  # until the next full hydration, which read as the delete having failed.
  defp apply_deletes(garage, deletes) do
    Enum.reduce(to_pairs(deletes, "key"), garage, fn {store, key}, acc ->
      case store_key(store) do
        {:list, field, id_key} ->
          Map.update!(acc, field, fn list ->
            Enum.reject(list, &(Map.get(&1, id_key) == key))
          end)

        {:singleton, field} ->
          Map.put(acc, field, nil)

        :unknown ->
          acc
      end
    end)
  end

  defp upsert_by(list, record, id_key) do
    id = Map.get(record, id_key)

    if Enum.any?(list, &(Map.get(&1, id_key) == id)) do
      Enum.map(list, fn existing ->
        if Map.get(existing, id_key) == id, do: record, else: existing
      end)
    else
      list ++ [record]
    end
  end

  defp store_key("vehicles"), do: {:list, :vehicles, "vehicle_id"}
  defp store_key("events"), do: {:list, :events, "event_id"}
  defp store_key("readings"), do: {:list, :readings, "reading_id"}
  defp store_key("usage"), do: {:list, :usage, "usage_id"}
  defp store_key("reminders"), do: {:list, :reminders, "reminder_id"}
  defp store_key("prefs"), do: {:singleton, :prefs}
  defp store_key("meta"), do: {:singleton, :meta}
  defp store_key(_), do: :unknown

  defp mark_unsaved(socket, mutation_id, reason \\ nil) do
    pending =
      Map.update(
        socket.assigns.pending_writes,
        mutation_id,
        %{status: :unsaved},
        &%{&1 | status: :unsaved}
      )

    already = Enum.any?(socket.assigns.unsaved_writes, &(&1.mutation_id == mutation_id))

    unsaved =
      if already,
        do: socket.assigns.unsaved_writes,
        else: socket.assigns.unsaved_writes ++ [%{mutation_id: mutation_id, reason: reason}]

    socket
    |> assign(:pending_writes, pending)
    |> assign(:unsaved_writes, unsaved)
  end

  defp check_version(%Envelope{schema_version: v}) do
    server = Envelope.current_schema_version()

    cond do
      v == server -> :ok
      v > server -> {:error, {:newer_than_server, v}}
      true -> Migrations.migrate(%{}, v, server) |> then(fn _ -> :ok end)
    end
  end

  defp storage_mode(%{"mode" => "durable_capable"}), do: :durable_capable
  defp storage_mode(%{"mode" => "idb"}), do: :durable_capable
  defp storage_mode(%{"mode" => "session_only"}), do: :session_only
  defp storage_mode(_), do: :unknown

  defp quota(%{"estimate" => %{"usage" => u, "quota" => q}}) when is_integer(u) and is_integer(q),
    do: %{usage: u, quota: q}

  defp quota(_), do: nil

  # >= 0.8 matches ADR-0004 §"Quota and eviction" (surfacing threshold). Guards
  # against q <= 0 mirror quota_line/1 in StorageStatusLive — a zero denominator
  # is not "under pressure", it is "no meaningful estimate".
  defp quota_pressured?(%{usage: usage, quota: q})
       when is_integer(usage) and is_integer(q) and q > 0,
       do: usage / q >= 0.8

  defp quota_pressured?(_), do: false

  # The validator returns wire-keyed (string) collections; the garage assign
  # is the atom-keyed shape every LiveView reads.
  defp to_garage(data) do
    %{
      vehicles: Map.get(data, "vehicles", []),
      events: Map.get(data, "events", []),
      readings: Map.get(data, "readings", []),
      usage: Map.get(data, "usage", []),
      reminders: Map.get(data, "reminders", []),
      prefs: Map.get(data, "prefs"),
      meta: Map.get(data, "meta")
    }
  end

  defp resolve_state(data, storage) do
    empty? = data.vehicles == [] and data.events == [] and data.readings == []

    # Empty stores with the meta singleton intact is what an INTENTIONAL
    # emptying looks like — deleting the last vehicle removes records, not the
    # protocol bookkeeping. Eviction and cleared site data take meta with
    # them. Without this distinction, deleting your last vehicle flipped the
    # next mount into :data_missing ("your records are gone"), whose screen
    # offers recovery and whose state refuses every write — the user who
    # chose an empty garage was locked out of starting again.
    emptied_on_purpose? =
      empty? and is_map(data.meta) and is_integer(data.meta["seq"]) and data.meta["seq"] > 0

    cond do
      storage_mode(storage) == :session_only -> :storage_unavailable
      not empty? -> :loaded
      emptied_on_purpose? -> :empty
      get_in(storage, ["boot_hint"]) == "has_data" -> :data_missing
      true -> :empty
    end
  end

  defp cancel_deadline(socket), do: assign(socket, :hydration_deadline_ref, nil)

  defp generate_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
