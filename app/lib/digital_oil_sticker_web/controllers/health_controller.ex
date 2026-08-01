defmodule DigitalOilStickerWeb.HealthController do
  @moduledoc """
  Liveness/readiness probe for the platform health check. Returns no personal
  data and takes no personal parameters (INV-4, INV-26).
  """
  use DigitalOilStickerWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", version: Application.spec(:digital_oil_sticker, :vsn) |> to_string()})
  end
end
