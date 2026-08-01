defmodule DigitalOilSticker.Catalog.SelectorTest do
  @moduledoc "AC-2: reject-never-strip, reject-never-coerce, no atom creation."
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog.{Selector, Vocabulary}

  @valid_year 2024

  test "a known-good selector validates" do
    assert {:ok, sel} = Selector.validate(:list_makes, %{"year" => @valid_year})
    assert sel.year == @valid_year
    assert sel.page_size == 50
  end

  test "unknown keys are rejected, never stripped" do
    for {key, value} <- [
          {"vin", "1HGCM82633A004352"},
          {"odometer", 84_213},
          {"notes", "leaks a bit"},
          {"tab_id", "3f1c"},
          {"vehicle_id", "0d9e"},
          {"q", "civ"},
          {"performed_on", "2026-01-04"},
          {"Year", @valid_year}
        ] do
      params = Map.put(%{"year" => @valid_year}, key, value)

      assert {:error, :invalid_selector} = Selector.validate(:list_makes, params),
             "extra key #{inspect(key)} must reject the whole selector"
    end
  end

  test "type coercion is refused" do
    for bad <- ["2024", 2024.0, [2024], %{"y" => 2024}, nil, true] do
      assert {:error, :invalid_selector} = Selector.validate(:list_makes, %{"year" => bad})
    end

    assert {:error, :invalid_selector} = Selector.validate(:list_makes, %{"year" => @valid_year, "page_size" => "50"})
  end

  test "years outside the catalog window are rejected (window from metadata, not hardcoded)" do
    {first, last} = DigitalOilSticker.Catalog.Metadata.window_years()
    assert {:error, :invalid_selector} = Selector.validate(:list_makes, %{"year" => first - 1})
    assert {:error, :invalid_selector} = Selector.validate(:list_makes, %{"year" => last + 1})
    assert {:ok, _} = Selector.validate(:list_makes, %{"year" => first})
    assert {:ok, _} = Selector.validate(:list_makes, %{"year" => last})
  end

  test "missing required keys are rejected" do
    assert {:error, :invalid_selector} = Selector.validate(:list_models, %{"year" => @valid_year})
    assert {:error, :invalid_selector} = Selector.validate(:get_configuration, %{})
  end

  test "page_size outside 1..200 is rejected, not clamped" do
    for bad <- [0, 201, -1, 5_000] do
      assert {:error, :invalid_selector} =
               Selector.validate(:list_makes, %{"year" => @valid_year, "page_size" => bad})
    end
  end

  test "catalog ids must match the id charset and length" do
    for bad <- ["", String.duplicate("a", 65), "UPPER", "with space", "semi;colon", "quote'"] do
      assert {:error, :invalid_selector} =
               Selector.validate(:get_configuration, %{"configuration_key" => bad})
    end
  end

  test "the selector struct cannot hold fields outside the vocabulary" do
    assert Map.keys(%Selector{function: :list_years}) -- [:__struct__, :function | Vocabulary.all_fields()] == []
  end

  test "every event allowlist key is in the global vocabulary" do
    for {event, keys} <- Vocabulary.event_allowlist(), key <- keys do
      assert match?({:ok, _}, Vocabulary.key_atom(key)), "#{event} allows #{key} which is not in the vocabulary"
    end
  end
end
