defmodule DigitalOilSticker.QR.Png do
  @moduledoc """
  QR → PNG via `EQRCode`. Pure function, no file I/O.

  Default width is 320px, which on most label and receipt printers lands in
  the 1–1.2 inch range — the familiar oil-change sticker size and well above
  the scanability threshold for a phone camera at arm's length. Callers can
  override `:width` per-sticker (a wall poster at 1024, a corner of a receipt
  at 180).
  """

  @default_width 320

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def render(url, opts) when is_binary(url) do
    width = Keyword.get(opts, :width, @default_width)

    try do
      png =
        url
        |> EQRCode.encode()
        |> EQRCode.PNG.png(width: width)
        |> IO.iodata_to_binary()

      {:ok, png}
    rescue
      ArgumentError -> {:error, :url_too_long}
    end
  end
end
