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

  # The public integration surface — Tekmetric / Shopmonkey / Shop-Ware / any
  # POS or DMS calls these. Wildcard CORS so a browser-based work-order screen
  # (Shopmonkey's is one) can POST directly without a proxy. No auth, no
  # session, no CSRF: the sticker code is the only thing the API knows, and
  # the sticker code is already a public token by design (see StickerCode's
  # moduledoc). The endpoint-wide RateLimit plug already covers abuse.
  pipeline :public_api do
    plug CORSPlug, origin: "*"
    # Request bodies are JSON. Response content types (image/png,
    # application/vnd.zebra.zpl, etc.) are set by the controller per format.
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
      live "/attribution", AttributionLive, :index
    end

    # A stranger scanning a windshield sticker lands here. Deliberately its
    # own live_session (no LocalStoreHook): no IndexedDB is loaded, no
    # per-user assigns are staged, no cross-user data leaks in either
    # direction (INV-23/25). The sticker's date/mileage/grade travels in the
    # URL fragment and never reaches the server (INV-26).
    live_session :scan do
      live "/s", ScanLive, :show
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

  # Public integration API. The sticker-generation surface a POS/DMS integrator
  # calls at end-of-work-order. Stateless, no auth, no CSRF, wildcard CORS.
  scope "/api/v1", DigitalOilStickerWeb.Api.V1 do
    pipe_through :public_api

    get "/formats", FormatController, :index
    post "/stickers", StickerController, :create
    # Grok-backed: free text → structured sticker. The hot path (POST
    # /stickers) does NOT touch Grok — only this endpoint does.
    post "/stickers/from-text", StickerController, :from_text
    # The code.format file-like path (e.g. /stickers/ABC123.png) lets a CDN
    # key off the whole last segment. Phoenix's router can't take two dynamic
    # segments between dots, so we match one and split in the controller.
    get "/stickers/:code_with_ext", StickerController, :show

    # CORS preflight. cors_plug (installed in `:public_api`) handles OPTIONS
    # itself via `halt`, but Phoenix needs a matching route to even enter the
    # pipeline — otherwise it returns 404 before cors_plug ever runs.
    match :options, "/*path", StickerController, :preflight
  end

  # Model Context Protocol endpoint. Any MCP-compatible LLM agent — Claude,
  # Grok, a shop's own AI assistant — can call the same sticker tools the
  # REST API exposes, through JSON-RPC 2.0 over HTTP.
  scope "/", DigitalOilStickerWeb do
    pipe_through :public_api

    post "/mcp", McpController, :handle
  end

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
