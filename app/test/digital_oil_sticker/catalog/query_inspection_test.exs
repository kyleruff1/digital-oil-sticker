defmodule DigitalOilSticker.Catalog.QueryInspectionTest do
  @moduledoc """
  DOS-M09-002 AC-17 / INV-26 — the reciprocal of impersonal_selector_test.

  impersonal_selector_test asserts the closed vocabulary from the Selector's
  side: an enumerated list of "obviously personal" strings is rejected.

  This test enumerates from the OTHER side: every field the app persists in
  local storage under Schema.V1 that carries user-supplied content or
  correlatable identifiers (`@vehicle_keys`, `@event_keys`, `@reading_keys`,
  `@usage_keys`, `@reminder_keys`) and asserts that name never appears in the
  catalog vocabulary and never wins acceptance from `Selector.validate/2` on
  any declared catalog function. The two tests together close the boundary:
  no personal identifier reaches the catalog layer, no matter which side you
  approach the vocabulary from.

  Also asserts a structural property of `Catalog.RateLimit` — the per-socket
  budget struct that any catalog-consuming LiveView carries in
  `assigns.catalog_budget` — its fields are all numeric, so no personal
  string could be recorded on it even if a caller tried.
  """

  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog.{RateLimit, Selector, Vocabulary}

  # Fields defined on Schema.V1 records that either carry user-supplied text
  # (nickname, notes, filter_text, oil_brand, oil_family) or are per-user
  # correlatable identifiers (any of the *_id keys, vin_last6, active_vehicle_id).
  # The point is not novelty — it is that these strings live in a namespace
  # the catalog layer must NEVER accept as query keys.
  @personal_persisted_keys ~w(
    vehicle_id
    event_id
    reading_id
    usage_id
    reminder_id
    vin_last6
    nickname
    notes
    oil_brand
    oil_family
    oil_base_stock
    oil_viscosity
    filter_text
    odometer_input_value
    active_vehicle_id
    correction_of
    source_ref
    severe_answers
    baseline_distance_per_week
    performed_at
    observed_at
    effective_from
    effective_to
    preferred_time
    last_write_at
  )

  describe "no persisted personal field is a catalog vocabulary key" do
    test "every persisted personal key is absent from Vocabulary.field_specs/0" do
      vocab_names =
        Vocabulary.field_specs()
        |> Map.keys()
        |> Enum.map(&Atom.to_string/1)
        |> MapSet.new()

      leaks = Enum.filter(@personal_persisted_keys, &MapSet.member?(vocab_names, &1))

      assert leaks == [],
             "these persisted personal field names leaked into the catalog vocabulary: " <>
               inspect(leaks)
    end
  end

  describe "Selector.validate rejects every persisted personal field on every catalog function" do
    for key <- @personal_persisted_keys do
      test "#{key} is rejected on every declared catalog function" do
        for {function, _spec} <- Vocabulary.function_specs() do
          assert {:error, :invalid_selector} =
                   Selector.validate(function, %{unquote(key) => "any-value"}),
                 "personal key #{unquote(key)} was accepted by catalog function #{function}"
        end
      end
    end
  end

  describe "the per-socket catalog budget cannot record a personal string" do
    test "RateLimit fields are all numeric" do
      bucket = RateLimit.new()

      for {field, value} <- Map.from_struct(bucket) do
        assert is_number(value),
               "RateLimit field #{inspect(field)} is not numeric (holds #{inspect(value)}); a non-numeric field could accidentally carry PII"
      end
    end

    test "RateLimit.take/3 never returns a struct with any string field" do
      {:ok, bucket} = RateLimit.take(RateLimit.new(30, 5, 0), 1, 100)

      for {field, value} <- Map.from_struct(bucket) do
        refute is_binary(value),
               "RateLimit field #{inspect(field)} became a string after take/3: #{inspect(value)}"
      end
    end
  end

  describe "the catalog vocabulary shape is closed to personal-namespace additions" do
    test "no vocabulary key ends in _id except the declared catalog id families" do
      allowed_id_keys = ~w(make_id model_id requirement_id filter_product_id)

      offending =
        Vocabulary.field_specs()
        |> Map.keys()
        |> Enum.map(&Atom.to_string/1)
        |> Enum.filter(&String.ends_with?(&1, "_id"))
        |> Kernel.--(allowed_id_keys)

      assert offending == [],
             "an unexpected *_id key entered the catalog vocabulary: " <>
               inspect(offending) <>
               ". *_id keys in the persisted-record namespace are correlatable; extend the allowlist deliberately."
    end
  end
end
