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
      {DNSCluster, query: Application.get_env(:digital_oil_sticker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DigitalOilSticker.PubSub},
      # Start a worker by calling: DigitalOilSticker.Worker.start_link(arg)
      # {DigitalOilSticker.Worker, arg},
      # Start to serve requests, typically the last entry
      DigitalOilStickerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DigitalOilSticker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DigitalOilStickerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

end
