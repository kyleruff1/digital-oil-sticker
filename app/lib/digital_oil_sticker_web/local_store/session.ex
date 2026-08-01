defmodule DigitalOilStickerWeb.LocalStore.Session do
  @moduledoc """
  The ONLY module that mutates the LocalStore protocol assigns. Holds the
  hydration state machine, the pending-write ledger, and the timeout arms.
  Personal data lives in `assigns.garage` for the socket lifetime only — it
  is never persisted, logged, or broadcast (INV-23/24).
  """
  import Phoenix.Component, only: [assign: 3]
  alias DigitalOilSticker.LocalStore.{Envelope, Migrations, Validation}

  @hydration_deadline_ms Application.compile_env(:digital_oil_sticker, :hydration_deadline_ms, 5_000)
  @ack_timeout_ms Application.compile_env(:digital_oil_sticker, :ack_timeout_ms, 2_000)

  @empty_garage %{vehicles: [], events: [], readings: [], usage: [], reminders: [], prefs: nil, meta: nil}

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
      |> assign(:quota, nil)
      |> assign(:cap_error, nil)
      |> assign(:garage, @empty_garage)
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
      socket
      |> cancel_deadline()
      |> assign(:seq, envelope.seq)
      |> assign(:quarantine, quarantine)
      |> assign(:storage_mode, storage_mode(envelope.storage))
      |> assign(:persist_granted, get_in(envelope.storage, ["persist_granted"]))
      |> assign(:quota, quota(envelope.storage))
      |> assign(:garage, to_garage(data))
      |> assign(:local_state, resolve_state(to_garage(data), envelope.storage))
    else
      {:error, {:newer_than_server, _}} ->
        socket
        |> cancel_deadline()
        |> assign(:read_only, true)
        |> assign(:local_state, :loaded)

      {:error, {:cap_exceeded, cap}} ->
        socket
        |> cancel_deadline()
        |> assign(:cap_error, cap)
        |> assign(:local_state, :storage_unavailable)

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
  """
  def stage_mutation(socket, upserts, deletes) do
    mutation_id = generate_id()
    seq = socket.assigns.seq + 1
    payload = Envelope.build_put(mutation_id, seq, to_pairs(upserts, "record"), to_pairs(deletes, "key"))

    pending =
      Map.put(socket.assigns.pending_writes, mutation_id, %{
        seq: seq,
        status: :saving,
        upserts: upserts,
        deletes: deletes
      })

    Process.send_after(self(), {:local_store_ack_timeout, mutation_id}, @ack_timeout_ms)

    socket =
      socket
      |> assign(:pending_writes, pending)
      |> assign(:seq, seq)
      |> assign(:garage, apply_upserts(socket.assigns.garage, upserts))
      |> Phoenix.LiveView.push_event("local_store:put", payload)

    {socket, mutation_id}
  end

  def handle_ack(socket, %{"mutation_id" => id, "status" => "ok"}) do
    {_write, pending} = Map.pop(socket.assigns.pending_writes, id)
    assign(socket, :pending_writes, pending)
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
    socket
    |> assign(:local_state, :hydrating)
    |> assign(:conflict_notice, true)
    |> Phoenix.LiveView.push_event("local_store:rehydrate", %{})
  end

  def mutations_enabled?(socket) do
    socket.assigns.local_state in [:loaded, :empty] and not socket.assigns.read_only and
      socket.assigns.storage_mode != :session_only
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

  defp upsert_by(list, record, id_key) do
    id = Map.get(record, id_key)

    if Enum.any?(list, &(Map.get(&1, id_key) == id)) do
      Enum.map(list, fn existing -> if Map.get(existing, id_key) == id, do: record, else: existing end)
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

  defp mark_unsaved(socket, mutation_id) do
    pending =
      Map.update(socket.assigns.pending_writes, mutation_id, %{status: :unsaved}, &%{&1 | status: :unsaved})

    assign(socket, :pending_writes, pending)
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

  defp quota(%{"estimate" => %{"usage" => u, "quota" => q}}) when is_integer(u) and is_integer(q), do: %{usage: u, quota: q}
  defp quota(_), do: nil

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

    cond do
      storage_mode(storage) == :session_only -> :storage_unavailable
      not empty? -> :loaded
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
