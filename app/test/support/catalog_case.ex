defmodule DigitalOilSticker.CatalogCase do
  @moduledoc """
  Test case for code that reads the catalog. The catalog is a read-only
  fixture SQLite artifact — there is no sandbox and no per-test ownership,
  because there are no writes and therefore no transactions to isolate.
  Async is safe: concurrent readers of an immutable file.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias DigitalOilSticker.CatalogRepo
      import Ecto.Query
      import DigitalOilSticker.CatalogCase
    end
  end

  @doc "Path of the fixture catalog the test env points at."
  def fixture_catalog_path do
    Application.get_env(:digital_oil_sticker, DigitalOilSticker.CatalogRepo)[:database]
  end
end
