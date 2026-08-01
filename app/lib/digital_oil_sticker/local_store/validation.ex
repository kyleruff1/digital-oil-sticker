defmodule DigitalOilSticker.LocalStore.Validation do
  @moduledoc """
  Read-time integrity pass over a decoded envelope (DOS-M09-001 FR-11/FR-12,
  DOS-M09-002 FR-7/FR-8).

  Caps are checked first; a payload over any hard cap is rejected outright
  with the cap named. Then every record is validated through
  `DigitalOilSticker.LocalStore.Schema.V1`. Validation failure is never
  fatal to the session and never silent: the valid subset hydrates as
  canonical data, and each failing record moves to a quarantine list naming
  the store, the record id when readable, and the violated rule. Nothing is
  repaired, nothing is deleted, and the raw payload stays exportable.

  After per-record validation a referential pass runs: any vehicle-scoped
  record whose `vehicle_id` is not among the validated vehicles quarantines
  with rule `:orphan_vehicle_id` — quarantined, never deleted, and never
  re-linked by inference.
  """

  alias DigitalOilSticker.LocalStore.{Caps, Envelope, Quarantine}
  alias DigitalOilSticker.LocalStore.Schema.V1

  @type result ::
          {:ok, %{data: map(), quarantine: [Quarantine.t()]}}
          | {:error, {:cap_exceeded, Caps.cap()}}

  @doc """
  Validates a decoded envelope whose decoded payload occupied `byte_size`
  bytes. Returns the canonical data plus the quarantine list, or a cap
  error.
  """
  @spec validate(Envelope.t(), non_neg_integer()) :: result()
  def validate(%Envelope{data: data} = envelope, byte_size) do
    with :ok <- Caps.check(envelope, byte_size) do
      {vehicles, vehicle_quarantine} =
        validate_collection(data["vehicles"], "vehicles", "vehicle_id", &V1.validate_vehicle/1)

      vehicle_ids = MapSet.new(vehicles, & &1["vehicle_id"])

      {events, event_quarantine} =
        data["events"]
        |> validate_collection("events", "event_id", &V1.validate_event/1)
        |> referential_pass("events", "event_id", vehicle_ids)

      {readings, reading_quarantine} =
        data["readings"]
        |> validate_collection("readings", "reading_id", &V1.validate_reading/1)
        |> referential_pass("readings", "reading_id", vehicle_ids)

      {usage, usage_quarantine} =
        data["usage"]
        |> validate_collection("usage", "usage_id", &V1.validate_usage/1)
        |> referential_pass("usage", "usage_id", vehicle_ids)

      {reminders, reminder_quarantine} =
        data["reminders"]
        |> validate_collection("reminders", "reminder_id", &V1.validate_reminder/1)
        |> referential_pass("reminders", "reminder_id", vehicle_ids)

      {meta, meta_quarantine} = validate_singleton(data["meta"], "meta", &V1.validate_meta/1)
      {prefs, prefs_quarantine} = validate_singleton(data["prefs"], "prefs", &V1.validate_prefs/1)

      quarantine =
        vehicle_quarantine ++
          event_quarantine ++
          reading_quarantine ++
          usage_quarantine ++
          reminder_quarantine ++
          meta_quarantine ++ prefs_quarantine

      canonical_data = %{
        "meta" => meta,
        "vehicles" => vehicles,
        "events" => events,
        "readings" => readings,
        "usage" => usage,
        "reminders" => reminders,
        "prefs" => prefs
      }

      {:ok, %{data: canonical_data, quarantine: quarantine}}
    end
  end

  ## Per-record pass

  defp validate_collection(records, store, id_key, validator) when is_list(records) do
    {valid, quarantined} =
      Enum.reduce(records, {[], []}, fn record, {valid, quarantined} ->
        case validator.(record) do
          {:ok, canonical} ->
            {[canonical | valid], quarantined}

          {:error, rule} ->
            entry = %Quarantine{store: store, id: readable_id(record, id_key), rule: rule}
            {valid, [entry | quarantined]}
        end
      end)

    {Enum.reverse(valid), Enum.reverse(quarantined)}
  end

  defp validate_collection(_not_a_list, _store, _id_key, _validator), do: {[], []}

  ## Referential pass

  defp referential_pass({records, quarantined}, store, id_key, vehicle_ids) do
    {linked, orphaned} =
      Enum.split_with(records, fn record -> MapSet.member?(vehicle_ids, record["vehicle_id"]) end)

    orphan_entries =
      Enum.map(orphaned, fn record ->
        %Quarantine{store: store, id: readable_id(record, id_key), rule: :orphan_vehicle_id}
      end)

    {linked, quarantined ++ orphan_entries}
  end

  ## Singletons

  defp validate_singleton(nil, _store, _validator), do: {nil, []}

  defp validate_singleton(record, store, validator) do
    case validator.(record) do
      {:ok, canonical} -> {canonical, []}
      {:error, rule} -> {nil, [%Quarantine{store: store, id: store, rule: rule}]}
    end
  end

  ## Helpers

  # Only the record's own id string may enter a quarantine entry — never any
  # other field value (INV-4).
  defp readable_id(record, id_key) when is_map(record) do
    case Map.get(record, id_key) do
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  defp readable_id(_record, _id_key), do: nil
end
