import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/digital_oil_sticker start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint, server: true
end

config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/digital_oil_sticker_web/router\.ex$"E,
        ~r"lib/digital_oil_sticker_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The catalog SQLite artifact is baked into the release image (ADR-0004).
  # It is opened read-only three ways: SQLITE_OPEN_READONLY, PRAGMA
  # query_only, and the repo module's read_only: true. journal_mode MUST be
  # nil — ecto_sqlite3 otherwise defaults it to :wal, and `PRAGMA
  # journal_mode = wal` writes the file header, which fails on a read-only
  # handle (and WAL needs a -shm file the immutable image layer cannot hold).
  catalog_path =
    System.get_env("CATALOG_DATABASE_PATH") ||
      Application.app_dir(:digital_oil_sticker, "priv/catalog/catalog.sqlite3")

  config :digital_oil_sticker, DigitalOilSticker.CatalogRepo,
    database: catalog_path,
    mode: :readonly,
    journal_mode: nil,
    after_connect: {Exqlite, :query!, ["PRAGMA query_only = ON", []]},
    pool_size: String.to_integer(System.get_env("CATALOG_POOL_SIZE") || "8"),
    show_sensitive_data_on_connection_error: false

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :digital_oil_sticker, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    # An explicit list, never `true` or `false` (FR-5). `false` disables the
    # check; `true` compares against :url above, which happens to be right
    # today and goes silently wrong the moment a second hostname is served.
    # The list lives in DigitalOilStickerWeb.Hosts so check_origin and the
    # CSP's connect-src cannot disagree about which hosts are ours.
    check_origin: DigitalOilStickerWeb.Hosts.allowed_origins(),
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
