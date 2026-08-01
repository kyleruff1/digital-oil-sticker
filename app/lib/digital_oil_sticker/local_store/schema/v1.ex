defmodule DigitalOilSticker.LocalStore.Schema.V1 do
  @moduledoc """
  Per-record validation for logical schema version 1 (DOS-M09-001 FR-11).

  Each validator takes an untrusted record map and returns
  `{:ok, canonical_map}` or `{:error, rule}` where `rule` is the atom naming
  the violated integrity rule. Validation never repairs, never fabricates a
  value, and never deletes — a failing record is quarantined by the caller.

  ## Unknown-key preservation (FR-10, AC-9)

  A record is never rejected for carrying a key this version does not
  recognize. Unknown keys are collected verbatim into a `"__unknown__"`
  submap on the canonical record, and `restore_unknown/1` merges them back
  flat for write-back, so an older deployment never destroys fields a newer
  one wrote.

  ## Rules

    * `:not_a_map` — the record is not a map
    * `:invalid_uuid` — a required id is missing or not UUIDv4-shaped
    * `:unparseable_instant` — a required/present instant or date does not
      parse as ISO 8601
    * `:invalid_odometer` — `odometer_m` is missing, not an integer, or
      negative (mileage is a non-negative integer in metres, the base unit)
    * `:invalid_unit` — a unit field is not `"mi"` or `"km"`
    * `:invalid_provenance_mode` — not `"catalog"` or `"manual"`
    * `:invalid_archived` — `archived` present but not a boolean
    * `:invalid_enabled` — `enabled` present but not a boolean
    * `:invalid_seq` — `meta.seq` present but not a non-negative integer
    * `:bad_version` — `meta.schema_version` present but not a positive
      integer
  """

  @unknown_key "__unknown__"

  @units ~w(mi km)
  @provenance_modes ~w(catalog manual)

  @uuid_v4 ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/

  @vehicle_keys ~w(vehicle_id nickname configuration_key catalog_data_version model_year
                   display_snapshot support_status vin_last6 archived maintenance_plan
                   created_at updated_at)
  @event_keys ~w(event_id vehicle_id performed_at odometer_m odometer_input_value input_unit
                 oil_brand oil_family oil_viscosity filter_text notes provenance_mode
                 correction_of created_at updated_at)
  @reading_keys ~w(reading_id vehicle_id observed_at odometer_m input_unit source source_ref
                   valid superseded_by created_at updated_at)
  @usage_keys ~w(usage_id vehicle_id baseline_distance_per_week unit severe_answers
                 condition effective_from effective_to created_at updated_at)
  @reminder_keys ~w(reminder_id vehicle_id kind lead_value lead_unit preferred_time
                    enabled created_at updated_at)
  @prefs_keys ~w(unit_system time_zone onboarding_version display dismissed_notices)
  @meta_keys ~w(schema_version seq created_at last_write_at write_count persist_granted log)

  @type result :: {:ok, map()} | {:error, atom()}

  @doc "Validates a `vehicles` record."
  @spec validate_vehicle(term()) :: result()
  def validate_vehicle(record) when is_map(record) do
    with :ok <- require_uuid(record, "vehicle_id"),
         :ok <- optional_boolean(record, "archived", :invalid_archived) do
      {:ok, canonicalize(record, @vehicle_keys)}
    end
  end

  def validate_vehicle(_record), do: {:error, :not_a_map}

  @doc "Validates an `events` record."
  @spec validate_event(term()) :: result()
  def validate_event(record) when is_map(record) do
    with :ok <- require_uuid(record, "event_id"),
         :ok <- require_uuid(record, "vehicle_id"),
         :ok <- require_instant(record, "performed_at"),
         :ok <- require_odometer(record),
         :ok <- require_unit(record, "input_unit"),
         :ok <- require_provenance_mode(record) do
      {:ok, canonicalize(record, @event_keys)}
    end
  end

  def validate_event(_record), do: {:error, :not_a_map}

  @doc "Validates a `readings` record."
  @spec validate_reading(term()) :: result()
  def validate_reading(record) when is_map(record) do
    with :ok <- require_uuid(record, "reading_id"),
         :ok <- require_uuid(record, "vehicle_id"),
         :ok <- require_instant(record, "observed_at"),
         :ok <- require_odometer(record),
         :ok <- require_unit(record, "input_unit") do
      {:ok, canonicalize(record, @reading_keys)}
    end
  end

  def validate_reading(_record), do: {:error, :not_a_map}

  @doc "Validates a `usage` record."
  @spec validate_usage(term()) :: result()
  def validate_usage(record) when is_map(record) do
    with :ok <- require_uuid(record, "usage_id"),
         :ok <- require_uuid(record, "vehicle_id"),
         :ok <- require_instant(record, "effective_from"),
         :ok <- optional_unit(record, "unit") do
      {:ok, canonicalize(record, @usage_keys)}
    end
  end

  def validate_usage(_record), do: {:error, :not_a_map}

  @doc "Validates a `reminders` record."
  @spec validate_reminder(term()) :: result()
  def validate_reminder(record) when is_map(record) do
    with :ok <- require_uuid(record, "reminder_id"),
         :ok <- require_uuid(record, "vehicle_id"),
         :ok <- optional_boolean(record, "enabled", :invalid_enabled) do
      {:ok, canonicalize(record, @reminder_keys)}
    end
  end

  def validate_reminder(_record), do: {:error, :not_a_map}

  @doc "Validates the `prefs` singleton."
  @spec validate_prefs(term()) :: result()
  def validate_prefs(record) when is_map(record) do
    with :ok <- optional_unit(record, "unit_system") do
      {:ok, canonicalize(record, @prefs_keys)}
    end
  end

  def validate_prefs(_record), do: {:error, :not_a_map}

  @doc "Validates the `meta` singleton."
  @spec validate_meta(term()) :: result()
  def validate_meta(record) when is_map(record) do
    with :ok <- optional_pos_integer(record, "schema_version", :bad_version),
         :ok <- optional_non_neg_integer(record, "seq", :invalid_seq),
         :ok <- optional_instant(record, "created_at"),
         :ok <- optional_instant(record, "last_write_at") do
      {:ok, canonicalize(record, @meta_keys)}
    end
  end

  def validate_meta(_record), do: {:error, :not_a_map}

  @doc """
  Restores a canonical record to its flat write-back shape, merging the
  `"__unknown__"` submap back as top-level keys byte-for-byte (AC-9).
  """
  @spec restore_unknown(map()) :: map()
  def restore_unknown(canonical) when is_map(canonical) do
    {unknown, known} = Map.pop(canonical, @unknown_key, %{})
    Map.merge(known, unknown)
  end

  ## Canonicalization

  # Known keys stay flat; every other key moves verbatim under "__unknown__".
  # A pre-existing "__unknown__" submap (a canonical record re-validated) is
  # merged rather than nested.
  defp canonicalize(record, known_keys) do
    {carried_unknown, record} =
      case Map.pop(record, @unknown_key) do
        {unknown, rest} when is_map(unknown) -> {unknown, rest}
        {_not_a_map_or_nil, rest} -> {%{}, rest}
      end

    {known, unknown} = Map.split(record, known_keys)
    unknown = Map.merge(carried_unknown, unknown)

    if unknown == %{} do
      known
    else
      Map.put(known, @unknown_key, unknown)
    end
  end

  ## Field rules

  defp require_uuid(record, key) do
    case Map.fetch(record, key) do
      {:ok, value} when is_binary(value) ->
        if Regex.match?(@uuid_v4, value), do: :ok, else: {:error, :invalid_uuid}

      _ ->
        {:error, :invalid_uuid}
    end
  end

  defp require_instant(record, key) do
    case Map.fetch(record, key) do
      {:ok, value} -> check_instant(value)
      :error -> {:error, :unparseable_instant}
    end
  end

  defp optional_instant(record, key) do
    case Map.fetch(record, key) do
      {:ok, nil} -> :ok
      {:ok, value} -> check_instant(value)
      :error -> :ok
    end
  end

  defp check_instant(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _dt, _offset} ->
        :ok

      {:error, _} ->
        case Date.from_iso8601(value) do
          {:ok, _date} -> :ok
          {:error, _} -> {:error, :unparseable_instant}
        end
    end
  end

  defp check_instant(_value), do: {:error, :unparseable_instant}

  defp require_odometer(record) do
    case Map.fetch(record, "odometer_m") do
      {:ok, value} when is_integer(value) and value >= 0 -> :ok
      _ -> {:error, :invalid_odometer}
    end
  end

  defp require_unit(record, key) do
    case Map.fetch(record, key) do
      {:ok, value} when value in @units -> :ok
      _ -> {:error, :invalid_unit}
    end
  end

  defp optional_unit(record, key) do
    case Map.fetch(record, key) do
      {:ok, nil} -> :ok
      {:ok, value} when value in @units -> :ok
      {:ok, _other} -> {:error, :invalid_unit}
      :error -> :ok
    end
  end

  defp require_provenance_mode(record) do
    case Map.fetch(record, "provenance_mode") do
      {:ok, value} when value in @provenance_modes -> :ok
      _ -> {:error, :invalid_provenance_mode}
    end
  end

  defp optional_boolean(record, key, rule) do
    case Map.fetch(record, key) do
      {:ok, value} when is_boolean(value) -> :ok
      {:ok, nil} -> :ok
      {:ok, _other} -> {:error, rule}
      :error -> :ok
    end
  end

  defp optional_pos_integer(record, key, rule) do
    case Map.fetch(record, key) do
      {:ok, value} when is_integer(value) and value > 0 -> :ok
      {:ok, nil} -> :ok
      {:ok, _other} -> {:error, rule}
      :error -> :ok
    end
  end

  defp optional_non_neg_integer(record, key, rule) do
    case Map.fetch(record, key) do
      {:ok, value} when is_integer(value) and value >= 0 -> :ok
      {:ok, nil} -> :ok
      {:ok, _other} -> {:error, rule}
      :error -> :ok
    end
  end
end
