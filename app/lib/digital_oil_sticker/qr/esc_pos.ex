defmodule DigitalOilSticker.QR.EscPos do
  @moduledoc """
  QR → ESC/POS, the Epson/Star thermal receipt-printer command set.

  Receipt printers are ESC/POS, not ZPL — the counter printer that prints the
  work-order receipt at Jiffy Lube is Epson or Star, not Zebra. Modern
  firmware encodes the QR itself, so we just send four commands:

    1. `GS ( k pL pH 49 65 cn 32`  — select model 2
    2. `GS ( k pL pH 49 67 size`   — module size (1..16, we pick 5)
    3. `GS ( k pL pH 49 69 ec`     — error correction level (48..51, we pick 49 = M)
    4. `GS ( k pL pH 49 80 48 data`  — store data
    5. `GS ( k pL pH 49 81 48`     — print

  `pL` and `pH` are the little-endian length of `(payload after the 2 bytes)`,
  which for the first three is 3, and for the data-store is `3 + len(data)`.

  Output is a raw byte string the caller pipes directly to the printer
  (over USB, a serial port, or a TCP connection to a networked unit).
  Content-Type when served over HTTP is `application/octet-stream`.
  """

  # Common byte constants
  @gs 0x1D
  @lparen 0x28
  @k 0x6B
  @cn_qr 49
  @model_fn 65
  @size_fn 67
  @ec_fn 69
  @store_fn 80
  @print_fn 81
  @data_prefix 48

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def render(url, opts) when is_binary(url) do
    size = Keyword.get(opts, :size, 5)
    ec_byte = ec_byte(Keyword.get(opts, :ec, :m))

    with :ok <- validate_size(size),
         {:ok, store_cmd} <- store_data(url) do
      bytes =
        IO.iodata_to_binary([
          # Select QR model 2 (type nominal 50, we use 32=0x50 as the default)
          header(4),
          @model_fn,
          <<50, 0>>,
          # Module size
          header(3),
          @size_fn,
          <<size>>,
          # Error correction
          header(3),
          @ec_fn,
          <<ec_byte>>,
          # Store the data
          store_cmd,
          # Print
          header(3),
          @print_fn,
          <<@data_prefix>>
        ])

      {:ok, bytes}
    end
  end

  # pL,pH is the little-endian length of (function bytes + payload) after it.
  # For a 3-byte payload (fn + one byte), this header carries len=3.
  defp header(len) do
    <<@gs, @lparen, @k, rem(len, 256), div(len, 256), @cn_qr>>
  end

  defp validate_size(n) when is_integer(n) and n >= 1 and n <= 16, do: :ok
  defp validate_size(_), do: {:error, :invalid_size}

  defp ec_byte(:l), do: 48
  defp ec_byte(:m), do: 49
  defp ec_byte(:q), do: 50
  defp ec_byte(:h), do: 51

  defp store_data(data) do
    bytes = :binary.bin_to_list(data)
    # Length = 3 (cn + fn + m) + bytes of data
    len = 3 + length(bytes)

    if len > 65535 do
      {:error, :url_too_long}
    else
      cmd =
        <<@gs, @lparen, @k, rem(len, 256), div(len, 256), @cn_qr, @store_fn, @data_prefix>> <>
          data

      {:ok, cmd}
    end
  end
end
