defmodule DigitalOilSticker.QR.Zpl do
  @moduledoc """
  QR → ZPL (Zebra Programming Language).

  ZPL is the dominant thermal-label-printer language: Zebra's full line, many
  Honeywell and Datamax units, and a long tail of knock-offs. The printer
  itself encodes the matrix — we just emit the field. That is the whole
  "no new hardware" argument to a Tekmetric or Shopmonkey partner: the
  printer on the shop's counter already knows how to draw this.

  ## Command layout (ZPL II, `^BQ`)

      ^XA                    ; start format
      ^FO<x>,<y>             ; field origin
      ^BQN,2,<magnification> ; QR barcode, model 2, size 1..10
      ^FDQA,<data>^FS        ; field data (QA = error correction + prefix)
      ^XZ                    ; end format

  Magnification 6 is the default here because on a 203 dpi printer (the most
  common shop unit) it produces a ~1 inch square QR — the same size the
  windshield sticker uses. Callers can override with `:magnification` in
  `[2..10]`.

  `QA,` on the `^FD` line is "no auto / quality level A" plus the data; it
  tells the printer not to try to guess an encoding mode. We rely on the
  caller passing a URL whose chars are in the QR alphanumeric set (the
  `/s#<base32>` form is all upper-case letters and digits except for the
  scheme prefix and `/s#`).
  """

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def render(url, opts) when is_binary(url) do
    x = Keyword.get(opts, :x, 50)
    y = Keyword.get(opts, :y, 50)

    with {:ok, magnification} <- validate_magnification(Keyword.get(opts, :magnification, 6)) do
      zpl =
        IO.iodata_to_binary([
          "^XA\n",
          "^FO",
          Integer.to_string(x),
          ",",
          Integer.to_string(y),
          "\n",
          "^BQN,2,",
          Integer.to_string(magnification),
          "\n",
          "^FDQA,",
          url,
          "^FS\n",
          "^XZ\n"
        ])

      {:ok, zpl}
    end
  end

  defp validate_magnification(m) when is_integer(m) and m >= 1 and m <= 10, do: {:ok, m}
  defp validate_magnification(_), do: {:error, :invalid_magnification}
end
