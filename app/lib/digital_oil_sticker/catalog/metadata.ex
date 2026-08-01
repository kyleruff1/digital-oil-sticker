defmodule DigitalOilSticker.Catalog.Metadata do
  @moduledoc """
  Reads catalog_metadata once at boot into :persistent_term and fails closed:
  a missing, unreadable, or schema-incompatible catalog stops the app rather
  than serving guesses. Within a machine's lifetime data_version cannot
  change (a deploy is a new OS process), which is what makes cache staleness
  structural rather than policed.
  """
  use GenServer

  @key {__MODULE__, :metadata}
  @supported_schema_versions ["1"]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    rows =
      Ecto.Adapters.SQL.query!(
        DigitalOilSticker.CatalogRepo,
        "SELECT key, value FROM catalog_metadata",
        []
      )

    meta = Map.new(rows.rows, fn [k, v] -> {k, v} end)

    schema_version = Map.fetch!(meta, "schema_version")

    unless schema_version in @supported_schema_versions do
      raise "catalog schema_version #{schema_version} unsupported (supported: #{inspect(@supported_schema_versions)})"
    end

    jm = Ecto.Adapters.SQL.query!(DigitalOilSticker.CatalogRepo, "PRAGMA journal_mode", [])

    unless jm.rows == [["delete"]],
      do: raise("catalog artifact must be journal_mode=delete, got #{inspect(jm.rows)}")

    :persistent_term.put(@key, %{
      schema_version: schema_version,
      data_version: Map.fetch!(meta, "data_version"),
      generated_at: Map.fetch!(meta, "generated_at"),
      window:
        {String.to_integer(Map.fetch!(meta, "window_start_year")),
         String.to_integer(Map.fetch!(meta, "window_end_year"))},
      market: Map.fetch!(meta, "market"),
      features: %{
        schedules: Map.get(meta, "feature_schedules", "absent"),
        oil_requirements: Map.get(meta, "feature_oil_requirements", "absent"),
        oil_products: Map.get(meta, "feature_oil_products", "withheld"),
        filters: Map.get(meta, "feature_filters", "absent")
      }
    })

    {:ok, %{}}
  end

  def supported_schema_versions, do: @supported_schema_versions

  def get, do: :persistent_term.get(@key)
  def data_version, do: get().data_version
  def schema_version, do: get().schema_version
  def window_years, do: get().window
  def feature(name), do: get().features |> Map.fetch!(name)
end
