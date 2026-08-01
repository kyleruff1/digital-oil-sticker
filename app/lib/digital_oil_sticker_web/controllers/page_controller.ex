defmodule DigitalOilStickerWeb.PageController do
  use DigitalOilStickerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
