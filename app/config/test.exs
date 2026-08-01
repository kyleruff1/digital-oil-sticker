import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Read-only fixture catalog. No sandbox: a sandbox is a transaction wrapper
# for writes, and a read-only connection holds none.
config :digital_oil_sticker, DigitalOilSticker.CatalogRepo,
  database: Path.expand("../priv/catalog/catalog.sqlite3", __DIR__),
  mode: :readonly,
  journal_mode: nil,
  after_connect: {Exqlite, :query!, ["PRAGMA query_only = ON", []]},
  pool_size: 5

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :digital_oil_sticker, DigitalOilStickerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "wIHRoUNIJxSWOLRe3vbIeIqIsOorzxpSafKfEjLA9jq4FxVATmat769eTJX7bOWd",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
