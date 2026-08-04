defmodule DigitalOilSticker.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DigitalOilStickerWeb.Telemetry,
      # Read-only catalog only. No Ecto.Migrator: the catalog is a build
      # artifact, not state — there is nothing to migrate at boot, and no
      # user repo exists on the server (INV-23).
      DigitalOilSticker.CatalogRepo,
      # Boot-time metadata read (fails closed on missing/incompatible catalog)
      # and the read-through result cache.
      DigitalOilSticker.Catalog.Metadata,
      # Our own oil model (grades, base stocks, engine classes, interval
      # rules) — small enough to hold in memory, and read at boot so a
      # catalog without it fails loudly instead of showing no intervals.
      DigitalOilSticker.Catalog.OilModel,
      DigitalOilSticker.Catalog.Cache,
      # Per-client concurrent-connect ceiling for the LiveView socket
      # (DOS-M09-007 FR-8). Owns an ETS counter keyed by
      # `ClientIP.client_key/1` — the socket connect passes through
      # `try_connect/2`, `release/1` runs at socket termination.
      DigitalOilStickerWeb.ConnectLimiter,
      # Owns the ETS table backing DigitalOilStickerWeb.Plugs.RateLimit. The
      # plug reads and writes the table directly on the request path; this
      # process exists only so the table's lifetime is the app's lifetime,
      # not a request's (DOS-M09-007 AC-6).
      DigitalOilStickerWeb.Plugs.RateLimitStore,
      {DNSCluster,
       query: Application.get_env(:digital_oil_sticker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DigitalOilSticker.PubSub},
      # Start a worker by calling: DigitalOilSticker.Worker.start_link(arg)
      # {DigitalOilSticker.Worker, arg},
      # Start to serve requests, typically the last entry
      DigitalOilStickerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DigitalOilSticker.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # Baseline for the readiness check: the artifact hash as it was when this
      # machine booted. Recorded after the repo is up (so the path resolves)
      # and before the endpoint takes traffic.
      DigitalOilStickerWeb.HealthController.record_boot_payload_sha256()
      {:ok, pid}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DigitalOilStickerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
