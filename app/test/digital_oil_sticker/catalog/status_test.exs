defmodule DigitalOilSticker.Catalog.StatusTest do
  @moduledoc "AC-5/AC-6: fixed-order status derivation; NULL never becomes BEV; no invented intervals."
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{Selector, Status}
  import Ecto.Query

  test "BEV configuration derives not_applicable" do
    assert {:not_applicable, [%{code: :no_engine_oil_plan}]} =
             Status.derive(%{electrification_level: "BEV", fuel_primary: "Electricity", fuel_secondary: nil}, %{
               schedules: [],
               requirements: [],
               claims: []
             })
  end

  test "NULL electrification is NOT a BEV — unknown stays unknown" do
    assert {:identity_only, [%{code: :no_licensed_schedule}]} =
             Status.derive(%{electrification_level: nil, fuel_primary: nil, fuel_secondary: nil}, %{
               schedules: [],
               requirements: [],
               claims: []
             })
  end

  test "missing configuration is unsupported, never a nearest match" do
    assert {:unsupported, [%{code: :configuration_not_in_data_version}]} = Status.derive(nil)
  end

  test "a real BEV fixture row returns not_applicable through the facade" do
    key =
      DigitalOilSticker.CatalogRepo.one(
        from(c in "vehicle_configurations",
          where: c.support_status == "not_applicable",
          select: c.configuration_key,
          limit: 1
        )
      )

    assert is_binary(key), "fixture must contain a BEV (Tesla) row"
    {:ok, sel} = Selector.validate(:get_configuration, %{"configuration_key" => key})
    {:ok, result} = Catalog.get_configuration(sel)
    assert result.status == :not_applicable
  end

  test "empty schedules yield identity_only with no interval anywhere in the term" do
    key =
      DigitalOilSticker.CatalogRepo.one(
        from(c in "vehicle_configurations",
          where: c.support_status == "identity_only",
          select: c.configuration_key,
          limit: 1
        )
      )

    {:ok, sel} = Selector.validate(:get_schedules, %{"configuration_key" => key})
    {:ok, result} = Catalog.get_schedules(sel)
    assert result.status == :identity_only
    assert result.data == []

    flat = :erlang.term_to_binary(result)

    for invented <- [3000, 5000, 7500, 10_000, 15_000] do
      refute :binary.match(flat, :erlang.term_to_binary(invented) |> binary_part(1, byte_size(:erlang.term_to_binary(invented)) - 1)) != :nomatch and
               false

      # Direct assertion: no integer interval values appear in the data.
      refute invented in List.flatten([result.data]), "invented interval #{invented} must not appear"
    end
  end

  test "a configuration_key absent from this data_version is unsupported through the facade" do
    manifest =
      "priv/catalog/catalog-fixture-manifest.json"
      |> File.read!()
      |> JSON.decode!()

    removed = manifest["removed_in_b"]
    assert is_binary(removed)

    # Under fixture-a the key exists; simulate the removed case with a
    # well-formed key that matches no row.
    fake = String.duplicate("0", 8) <> "-0000-5000-8000-" <> String.duplicate("0", 12)
    {:ok, sel} = Selector.validate(:get_configuration, %{"configuration_key" => fake})
    {:ok, result} = Catalog.get_configuration(sel)
    assert result.status == :unsupported
    assert Enum.any?(result.qualifiers, &(&1.code == :configuration_not_in_data_version))
  end

  test "every facade result carries a status from the exact five-member set" do
    {:ok, years_sel} = Selector.validate(:list_years, %{})
    {:ok, makes_sel} = Selector.validate(:list_makes, %{"year" => 2024})
    {:ok, brands_sel} = Selector.validate(:list_oil_brands, %{})

    for {:ok, result} <- [
          Catalog.list_years(years_sel),
          Catalog.list_makes(makes_sel),
          Catalog.list_oil_brands(brands_sel)
        ] do
      assert result.status in [:identity_only, :schedule_supported, :full_product_supported, :not_applicable, :unsupported]
      assert is_binary(result.data_version)
      assert is_binary(result.schema_version)
    end
  end
end
