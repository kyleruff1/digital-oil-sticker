defmodule DigitalOilSticker.QR.SvgTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR.Svg

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"

  describe "render/2" do
    test "emits a well-formed SVG root with namespace and viewBox" do
      assert {:ok, svg} = Svg.render(@url, [])
      assert is_binary(svg)

      # Root element present.
      assert svg =~ "<svg"

      # The SVG namespace is required for a browser to render it.
      assert svg =~ "xmlns=\"http://www.w3.org/2000/svg\""

      # viewBox was requested in render/2 (viewbox: true) — this is what
      # lets the browser scale the SVG to the shop's own stylesheet size.
      assert svg =~ "viewBox"
    end

    test "contains cell shapes drawn from the QR matrix" do
      {:ok, svg} = Svg.render(@url, [])

      # EQRCode emits either <rect> or <path> cells; accept either so a
      # library upgrade doesn't break this test on a cosmetic change.
      assert svg =~ "<rect" or svg =~ "<path"
    end

    test "returns :url_too_long for a URL that overflows QR capacity" do
      url = String.duplicate("a", 5000)
      assert {:error, :url_too_long} = Svg.render(url, [])
    end
  end
end
