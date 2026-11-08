defmodule DigitalOilSticker.StickerTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.{Sticker, StickerCode}

  # A real catalog UUID from the Vectors file's exemplar.
  @key "11111111-2222-4333-8444-555555555555"

  describe "from_params/1" do
    test "parses the canonical JSON shape (string keys, ISO date, integer metres)" do
      params = %{
        "configuration_key" => @key,
        "changed_on" => "2026-11-01",
        "odometer_m" => 72_420_480,
        "grade" => "5W-30",
        "base_stock" => "full_synthetic"
      }

      assert {:ok, sticker} = Sticker.from_params(params)
      assert sticker.configuration_key == @key
      assert sticker.changed_on == ~D[2026-11-01]
      assert sticker.odometer_m == 72_420_480
      assert sticker.grade == "5W-30"
      assert sticker.base_stock == "full_synthetic"
    end

    test "accepts odometer + odometer_unit in miles and converts to metres" do
      params = %{"configuration_key" => @key, "odometer" => 45_000, "odometer_unit" => "mi"}

      assert {:ok, sticker} = Sticker.from_params(params)
      assert sticker.odometer_m == 72_420_480
    end

    test "accepts odometer in kilometres and converts to metres" do
      params = %{"configuration_key" => @key, "odometer" => 100, "odometer_unit" => "km"}

      assert {:ok, sticker} = Sticker.from_params(params)
      assert sticker.odometer_m == 100_000
    end

    test "allows sparse params — only configuration_key is required by StickerCode" do
      assert {:ok, sticker} = Sticker.from_params(%{"configuration_key" => @key})
      assert sticker.changed_on == nil
      assert sticker.odometer_m == nil
      assert sticker.grade == nil
      assert sticker.base_stock == nil

      assert {:ok, _code} = StickerCode.encode(sticker)
    end

    test "rejects an invalid ISO date" do
      params = %{"configuration_key" => @key, "changed_on" => "not-a-date"}
      assert {:error, :invalid_date} = Sticker.from_params(params)
    end

    test "rejects a negative odometer in miles" do
      params = %{"configuration_key" => @key, "odometer" => -5, "odometer_unit" => "mi"}
      assert {:error, :odometer_out_of_range} = Sticker.from_params(params)
    end

    test "rejects a non-map" do
      assert {:error, :invalid_params} = Sticker.from_params(nil)
      assert {:error, :invalid_params} = Sticker.from_params("foo")
    end
  end

  describe "round-trip with StickerCode" do
    test "params → sticker → encode → decode → normalized sticker" do
      params = %{
        "configuration_key" => @key,
        "changed_on" => "2026-11-01",
        "odometer_m" => 72_420_480,
        "grade" => "5W-30",
        "base_stock" => "full_synthetic"
      }

      {:ok, sticker} = Sticker.from_params(params)
      {:ok, code} = StickerCode.encode(sticker)
      {:ok, decoded} = StickerCode.decode(code)

      assert decoded == sticker
    end
  end

  describe "canonical_url/2" do
    test "builds the scanner URL with the code in the fragment, not the path" do
      url = Sticker.canonical_url("ABCDEFGH", "digitaloilsticker.com")
      assert url == "https://digitaloilsticker.com/s#ABCDEFGH"
    end

    test "the fragment never travels server-side — mirrors the live sticker page" do
      url = Sticker.canonical_url("CODE", "example.test")
      # Everything after # is the client's business, never a request path.
      assert String.contains?(url, "#CODE")
      refute String.contains?(url, "/CODE")
      refute String.contains?(url, "?CODE")
    end
  end
end
