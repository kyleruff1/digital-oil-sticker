defmodule DigitalOilSticker.QR.PngTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR.Png

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  describe "render/2" do
    test "emits a valid PNG with the 8-byte signature, IHDR, and IEND framing" do
      assert {:ok, bytes} = Png.render(@url, [])
      assert <<@png_signature, rest::binary>> = bytes

      # IHDR is the first chunk (always starts 4 bytes in after the sig).
      # Chunk framing: 4-byte length, 4-byte type, N-byte data, 4-byte CRC.
      assert <<_len::32, "IHDR", _ihdr::binary>> = rest

      # IEND is the last chunk — zero-length, type "IEND", 4-byte CRC.
      # Looking at the trailing 12 bytes confirms the file is terminated.
      last_12 = binary_part(bytes, byte_size(bytes) - 12, 12)
      assert <<0::32, "IEND", _crc::32>> = last_12
    end

    test "returns a non-empty binary, not iodata" do
      assert {:ok, bytes} = Png.render(@url, [])
      assert is_binary(bytes)
      assert byte_size(bytes) > 100
    end

    test "honors the :width option by producing a larger file for a larger width" do
      {:ok, small} = Png.render(@url, width: 160)
      {:ok, large} = Png.render(@url, width: 640)

      # Width doesn't perfectly linearly scale PNG size (compression smooths
      # it), but a 4× width should produce a visibly larger file.
      assert byte_size(large) > byte_size(small)
    end

    test "returns :url_too_long for a URL that overflows QR capacity" do
      # QR version 40 at EC level L caps around 2953 bytes for binary data.
      # 5000 bytes guarantees overflow. EQRCode raises ArgumentError;
      # the renderer rescues it into a typed error.
      url = String.duplicate("a", 5000)
      assert {:error, :url_too_long} = Png.render(url, [])
    end
  end
end
