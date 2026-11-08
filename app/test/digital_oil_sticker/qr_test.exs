defmodule DigitalOilSticker.QRTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789ABCDEFGH23456789ABCDEFGH"

  describe "formats/0" do
    test "includes every format render/3 knows about" do
      for fmt <- QR.formats() do
        assert {:ok, _} = QR.render(@url, fmt)
      end
    end
  end

  describe "parse_format/1" do
    test "accepts atoms and strings for known formats" do
      assert {:ok, :png} = QR.parse_format(:png)
      assert {:ok, :png} = QR.parse_format("png")
      assert {:ok, :zpl} = QR.parse_format("zpl")
      assert {:ok, :esc_pos} = QR.parse_format("esc_pos")
    end

    test "rejects anything else" do
      assert {:error, :unknown_format} = QR.parse_format("gif")
      assert {:error, :unknown_format} = QR.parse_format(:gif)
      assert {:error, :unknown_format} = QR.parse_format(nil)
      assert {:error, :unknown_format} = QR.parse_format(42)
    end
  end

  describe "render(:unknown, ...)" do
    test "returns {:error, :unknown_format} without raising" do
      assert {:error, :unknown_format} = QR.render(@url, :bogus)
    end
  end

  describe "PNG" do
    test "produces bytes with the PNG signature" do
      {:ok, png} = QR.render(@url, :png)
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = png
    end

    test "respects :width option" do
      {:ok, small} = QR.render(@url, :png, width: 100)
      {:ok, large} = QR.render(@url, :png, width: 400)
      # Larger width → larger byte size (strictly, since the matrix is the same
      # and only the raster scales).
      assert byte_size(large) > byte_size(small)
    end
  end

  describe "SVG" do
    test "produces an <svg> element containing the matrix" do
      {:ok, svg} = QR.render(@url, :svg)
      assert String.contains?(svg, "<svg")
      assert String.contains?(svg, "</svg>")
      # The matrix is drawn as rects or paths — either way there are many of them.
      assert String.contains?(svg, "<rect") or String.contains?(svg, "<path")
    end
  end

  describe "ZPL" do
    test "emits the Zebra QR command with our URL as the field data" do
      {:ok, zpl} = QR.render(@url, :zpl)
      assert String.starts_with?(zpl, "^XA")
      assert String.ends_with?(String.trim(zpl), "^XZ")
      assert String.contains?(zpl, "^BQN,2,")
      assert String.contains?(zpl, "^FDQA," <> @url <> "^FS")
    end

    test "default magnification is 6" do
      {:ok, zpl} = QR.render(@url, :zpl)
      assert String.contains?(zpl, "^BQN,2,6")
    end

    test "respects :magnification option" do
      {:ok, zpl} = QR.render(@url, :zpl, magnification: 8)
      assert String.contains?(zpl, "^BQN,2,8")
    end

    test "rejects magnification out of [1..10]" do
      assert {:error, :invalid_magnification} = QR.render(@url, :zpl, magnification: 0)
      assert {:error, :invalid_magnification} = QR.render(@url, :zpl, magnification: 11)
    end
  end

  describe "ESC/POS" do
    test "emits the GS ( k command sequence" do
      {:ok, bytes} = QR.render(@url, :esc_pos)
      # Every command begins with GS ( k = 0x1D 0x28 0x6B
      assert <<0x1D, 0x28, 0x6B, _::binary>> = bytes
    end

    test "embeds the full URL in the data-store command" do
      {:ok, bytes} = QR.render(@url, :esc_pos)
      assert :binary.match(bytes, @url) != :nomatch
    end

    test "ends with the print command (function 81 = 0x51)" do
      {:ok, bytes} = QR.render(@url, :esc_pos)
      # Last 8 bytes are: GS ( k pL pH 0x31 0x51 0x30
      tail = binary_part(bytes, byte_size(bytes) - 8, 8)
      assert <<0x1D, 0x28, 0x6B, 3, 0, 49, 0x51, 0x30>> = tail
    end
  end

  describe "EPL" do
    test "emits the b command with the URL quoted" do
      {:ok, epl} = QR.render(@url, :epl)
      assert String.starts_with?(epl, "N\n")
      assert String.contains?(epl, "b50,50,Q")
      assert String.contains?(epl, "\"" <> @url <> "\"")
      assert String.ends_with?(String.trim(epl), "P1")
    end
  end

  describe "TSPL" do
    test "emits the QRCODE command with the URL quoted" do
      {:ok, tspl} = QR.render(@url, :tspl)
      assert String.contains?(tspl, "QRCODE ")
      assert String.contains?(tspl, "\"" <> @url <> "\"")
      assert String.contains?(tspl, "PRINT 1")
    end
  end
end
