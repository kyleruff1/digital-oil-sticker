defmodule DigitalOilStickerWeb.Api.V1.FormatController do
  @moduledoc """
  GET /api/v1/formats — the format allowlist. One place to read it so an
  integrator discovering the surface does not have to parse our docs.
  """
  use DigitalOilStickerWeb, :controller

  alias DigitalOilSticker.QR

  def index(conn, _params) do
    formats =
      Enum.map(QR.formats(), fn f ->
        %{
          name: Atom.to_string(f),
          content_type: content_type_for(f),
          description: description_for(f)
        }
      end)

    json(conn, %{formats: formats})
  end

  defp content_type_for(:png), do: "image/png"
  defp content_type_for(:svg), do: "image/svg+xml"
  defp content_type_for(:zpl), do: "application/vnd.zebra.zpl"
  defp content_type_for(:esc_pos), do: "application/octet-stream"
  defp content_type_for(:epl), do: "application/vnd.zebra.epl"
  defp content_type_for(:tspl), do: "application/vnd.tsc.tspl"

  defp description_for(:png), do: "Raster image, universal — inline via data URI or save to disk."
  defp description_for(:svg), do: "Vector image — scale losslessly, inline into HTML."

  defp description_for(:zpl),
    do: "Zebra Programming Language. Pipe directly to a Zebra or compatible label printer."

  defp description_for(:esc_pos),
    do: "Epson/Star thermal receipt-printer bytes. GS ( k native QR command."

  defp description_for(:epl),
    do: "Eltron Programming Language. Legacy Zebra-branded units."

  defp description_for(:tspl),
    do: "TSC Printer Language. TSC, Argox, Godex, and compatibles."
end
