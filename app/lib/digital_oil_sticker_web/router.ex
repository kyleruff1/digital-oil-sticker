defmodule DigitalOilStickerWeb.Router do
  use DigitalOilStickerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DigitalOilStickerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DigitalOilStickerWeb do
    pipe_through :browser

    live_session :garage, on_mount: {DigitalOilStickerWeb.LocalStoreHook, :default} do
      live "/", StickerLive, :index
      live "/vehicle", VehicleProfileLive, :show
      live "/vehicle/select", VehiclePickerLive, :select
      live "/service/new", OilChangeLive, :new
      live "/history", HistoryLive, :index
      live "/settings/storage", StorageStatusLive, :index
    end
  end

  scope "/", DigitalOilStickerWeb do
    pipe_through :api

    # Three distinct questions, three endpoints. Liveness must not consult
    # dependencies (a dependency failure would restart every machine instead
    # of rotating it out); readiness must consult all of them.
    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
    get "/version", HealthController, :version
  end

  # Other scopes may use custom stacks.
  # scope "/api", DigitalOilStickerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:digital_oil_sticker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DigitalOilStickerWeb.Telemetry
    end
  end
end
