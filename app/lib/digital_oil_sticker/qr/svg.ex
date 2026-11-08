defmodule DigitalOilSticker.QR.Svg do
  @moduledoc """
  QR → SVG via `EQRCode`.

  SVG is the default format when a shop's system renders the sticker inside
  a web view (Shopmonkey's work-order screen, Shop-Ware's print preview): the
  browser scales it losslessly to whatever label size the shop's own
  stylesheet picks, and the file is inline-able with no data-URI overhead.
  """

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def render(url, opts) when is_binary(url) do
    width = Keyword.get(opts, :width, 320)

    try do
      svg =
        url
        |> EQRCode.encode()
        |> EQRCode.SVG.svg(width: width, viewbox: true)

      {:ok, svg}
    rescue
      ArgumentError -> {:error, :url_too_long}
    end
  end
end
