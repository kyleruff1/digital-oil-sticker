defmodule DigitalOilSticker.QR.EscPosTest do
  @moduledoc """
  ESC/POS QR commands per Epson's spec. Every QR command starts with the
  three-byte prefix `GS ( k` = `<<0x1D, 0x28, 0x6B>>`, then a little-endian
  length, then `cn = 49` (QR), then a function code:

    - 65 (model)
    - 67 (size)
    - 69 (error correction)
    - 80 (store data), followed by the fixed prefix byte 0x30 and then the URL
    - 81 (print), followed by the fixed prefix byte 0x30
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR.EscPos

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"
  @gs_lparen_k <<0x1D, 0x28, 0x6B>>

  describe "render/2" do
    test "emits a binary starting with the GS ( k QR command prefix" do
      assert {:ok, bytes} = EscPos.render(@url, [])
      assert is_binary(bytes)
      assert binary_part(bytes, 0, 3) == @gs_lparen_k
    end

    test "contains the four function codes in order (model, size, EC, store, print)" do
      {:ok, bytes} = EscPos.render(@url, [])

      # Model-select is the first command (3 payload bytes + the function):
      # GS ( k 04 00 49 65 <two bytes>
      assert bytes =~ <<0x1D, 0x28, 0x6B, 4, 0, 49, 65>>

      # Size command: GS ( k 03 00 49 67 <size>
      assert bytes =~ <<0x1D, 0x28, 0x6B, 3, 0, 49, 67>>

      # EC command: GS ( k 03 00 49 69 <ec>
      assert bytes =~ <<0x1D, 0x28, 0x6B, 3, 0, 49, 69>>

      # Store command: GS ( k <len> 49 80 48 <data...> — data prefix 0x30 = 48.
      assert bytes =~ <<49, 80, 48>>

      # Print command: GS ( k 03 00 49 81 48
      assert bytes =~ <<0x1D, 0x28, 0x6B, 3, 0, 49, 81, 48>>
    end

    test "carries the URL verbatim after the store-data function header" do
      {:ok, bytes} = EscPos.render(@url, [])
      # The store command's data section is `49, 80, 48` + URL bytes.
      assert bytes =~ <<49, 80, 48>> <> @url
    end

    test "rejects out-of-range size with :invalid_size" do
      assert {:error, :invalid_size} = EscPos.render(@url, size: 0)
      assert {:error, :invalid_size} = EscPos.render(@url, size: 17)
    end

    test "returns :url_too_long when the data section would exceed 65535 bytes" do
      # Length field is two little-endian bytes = 65535 max. The store
      # command adds 3 to the data length (cn + fn + m), so anything over
      # 65532 bytes trips the guard.
      url = String.duplicate("a", 65_600)
      assert {:error, :url_too_long} = EscPos.render(url, [])
    end
  end
end
