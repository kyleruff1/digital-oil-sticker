defmodule DigitalOilStickerWeb.Router do
  use DigitalOilStickerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DigitalOilStickerWeb.Layouts, :root}
    plug :protect_from_forgery
    # No :put_secure_browser_headers — DigitalOilStickerWeb.Plugs.SecurityHeaders
    # owns the whole set at the endpoint level. Running both served two CSP
    # headers, and the enforcing one was Phoenix's weak default.
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
    # The browser posts violation reports here. No CSRF token accompanies a
    # report, and the endpoint performs no action — it reads a scrubbed record
    # into the log and answers 204.
    post "/csp-report", CSPReportController, :create

    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
    get "/version", HealthController, :version
  end

  # Other scopes may use custom stacks.
  # scope "/api", DigitalOilStickerWeb do
  #   pipe_through :api
  # end

  # No LiveDashboard.
  #
  # The generator ships a `/dev/dashboard` route guarded by `dev_routes`, but
  # `if` compiles both branches, so the guard only decides whether the route is
  # REACHABLE — the dependency still has to be present in every environment for
  # the router to compile. That meant a debug UI in the production release that
  # nobody here has ever opened, alongside a request-log tap the endpoint
  # mounted unconditionally.
  #
  # Removing the route removes the reason to carry the dependency at all.
  # Metrics still exist (DigitalOilStickerWeb.Telemetry); what is gone is the
  # web UI for reading them off a production machine.
end
