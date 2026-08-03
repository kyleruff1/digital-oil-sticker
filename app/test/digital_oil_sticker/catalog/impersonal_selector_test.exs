defmodule DigitalOilSticker.Catalog.ImpersonalSelectorTest do
  @moduledoc """
  AC-11 / FR-12 / INV-26: the catalog-query port accepts only impersonal
  selectors. No callback signature accepts a VIN, odometer, note, vehicle_id,
  event_id, or any client identifier.

  The Selector's closed vocabulary is the structural enforcement: `atomize_keys`
  rejects any key not in `Vocabulary.key_atoms/0`, so a personal identifier
  cannot reach a query even if someone tries to pass one. This test proves that
  property holds and names the specific personal fields it must reject.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog.{Selector, Vocabulary}

  @personal_keys ~w(
    vin vehicle_id event_id reading_id odometer odometer_m
    notes note nickname user_id tab_id session_id
    performed_at created_at updated_at
    oil_base_stock oil_viscosity filter_text
    active_vehicle_id
  )

  describe "the vocabulary contains no personal field" do
    test "every declared field is an impersonal catalog selector" do
      field_names =
        Vocabulary.field_specs()
        |> Map.keys()
        |> Enum.map(&Atom.to_string/1)
        |> MapSet.new()

      personal_present = Enum.filter(@personal_keys, &(&1 in field_names))

      assert personal_present == [],
             "the catalog vocabulary contains personal identifiers: #{inspect(personal_present)}"
    end
  end

  describe "the Selector rejects personal identifiers" do
    for key <- @personal_keys do
      test "rejects #{key} on every catalog function" do
        for {function, _spec} <- Vocabulary.function_specs() do
          assert {:error, :invalid_selector} =
                   Selector.validate(function, %{unquote(key) => "test-value"}),
                 "#{unquote(key)} was accepted by #{function}"
        end
      end
    end
  end

  test "the Selector rejects unknown keys entirely, not by name-matching" do
    assert {:error, :invalid_selector} =
             Selector.validate(:list_years, %{"garage" => "anything"})

    assert {:error, :invalid_selector} =
             Selector.validate(:list_years, %{"assigns" => "anything"})

    assert {:error, :invalid_selector} =
             Selector.validate(:list_years, %{"envelope" => "anything"})
  end
end
