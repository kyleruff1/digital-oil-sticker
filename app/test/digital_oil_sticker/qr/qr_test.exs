defmodule DigitalOilSticker.QRTest do
  @moduledoc """
  Top-level QR dispatcher: format parsing, format list, render dispatch.
  The per-format byte-level assertions live in the sibling files.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"

  describe "formats/0" do
    test "returns every format the renderer supports" do
      formats = QR.formats()
      assert :png in formats
      assert :svg in formats
      assert :zpl in formats
      assert :esc_pos in formats
      assert :epl in formats
      assert :tspl in formats
      assert length(formats) == 6
    end
  end

  describe "parse_format/1" do
    test "accepts matching atoms" do
      for f <- QR.formats() do
        assert QR.parse_format(f) == {:ok, f}
      end
    end

    test "accepts matching strings" do
      assert QR.parse_format("png") == {:ok, :png}
      assert QR.parse_format("svg") == {:ok, :svg}
      assert QR.parse_format("zpl") == {:ok, :zpl}
      assert QR.parse_format("esc_pos") == {:ok, :esc_pos}
      assert QR.parse_format("epl") == {:ok, :epl}
      assert QR.parse_format("tspl") == {:ok, :tspl}
    end

    test "rejects unknown names with :unknown_format" do
      assert QR.parse_format("gif") == {:error, :unknown_format}
      assert QR.parse_format(:gif) == {:error, :unknown_format}
      assert QR.parse_format(nil) == {:error, :unknown_format}
      assert QR.parse_format(123) == {:error, :unknown_format}
    end
  end

  describe "render/3 dispatch" do
    test "delegates to the per-format module for every supported format" do
      for format <- QR.formats() do
        assert {:ok, bytes} = QR.render(@url, format, [])
        assert is_binary(bytes)
        assert byte_size(bytes) > 0
      end
    end

    test "returns :unknown_format for an unlisted atom instead of crashing" do
      # The function clause for every known atom is handled; an unknown
      # atom falls through to the catch-all clause. This is a cheaper
      # safety check than relying on the controller to pre-filter.
      assert QR.render(@url, :gif, []) == {:error, :unknown_format}
    end
  end

  describe "url_too_long propagation" do
    # A URL longer than any QR version 40 can hold (≈2953 bytes for
    # alphanumeric, less for binary) overflows EQRCode's capacity. The PNG
    # and SVG renderers rescue it; ESC/POS has an explicit 65535-byte cap.
    # ZPL/EPL/TSPL emit the command string without pre-validating length —
    # the printer refuses later — which is honest for a printer-native
    # format where the printer is the real constraint.
    test "PNG returns :url_too_long for an oversized URL" do
      url = String.duplicate("a", 5000)
      assert {:error, :url_too_long} = QR.render(url, :png, [])
    end

    test "SVG returns :url_too_long for an oversized URL" do
      url = String.duplicate("a", 5000)
      assert {:error, :url_too_long} = QR.render(url, :svg, [])
    end
  end
end
