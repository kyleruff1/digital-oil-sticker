defmodule DigitalOilSticker.NoRuntimeCatalogSourcesTest do
  @moduledoc """
  M01-004 AC-5: no app-core flow invokes vPIC, FuelEconomy.gov, or any other
  catalog data provider at runtime. The catalog artifact is built offline in
  the `tools/catalog/` pipeline, baked into the Fly image, and read from
  `CatalogRepo` — the request path never talks to a third-party origin
  (INV-4, INV-27, ADR-0004 §"Catalog database on Fly").

  This is a source-scan enforcement, not a network monitor. The point is to
  fail the moment a `fetch()` or `Req.get()` call to a data-provider host
  lands in `lib/` or `assets/js/`, not to discover it in production logs.
  """
  use ExUnit.Case, async: true

  @app_root Path.expand("../..", __DIR__)

  # Third-party catalog data-provider hostnames + generic fetch/HTTP-client
  # call sites in the app source. `tools/catalog/` is the OFFLINE builder and
  # is allowed to call these; that directory is not scanned.
  @forbidden_patterns [
    ~r{\bvpic\.nhtsa\.dot\.gov\b}i,
    ~r{\bfueleconomy\.gov\b}i,
    ~r{\bengineoil\.api\.org\b}i,
    ~r{\bapi\.org\b}i,
    ~r{\bMotorcraft\b}i
  ]

  @source_roots ~w(lib assets/js)

  defp source_files do
    for root <- @source_roots,
        pattern <- ["**/*.ex", "**/*.exs", "**/*.js", "**/*.ts", "**/*.mjs"],
        path <- Path.wildcard(Path.join([@app_root, root, pattern])),
        Path.basename(path) != "no_runtime_catalog_sources_test.exs" do
      {Path.relative_to(path, @app_root),
       path |> File.read!() |> String.replace("\r\n", "\n")}
    end
  end

  defp strip_comments(source, ext) do
    prefix =
      case ext do
        ".ex" -> "#"
        ".exs" -> "#"
        _ -> "//"
      end

    source
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?(prefix)))
    |> Enum.join("\n")
  end

  test "no source file references any third-party catalog data provider" do
    sources = source_files()
    assert length(sources) > 5, "no source files scanned — glob is broken"

    offenders =
      for {path, source} <- sources,
          code = strip_comments(source, Path.extname(path)),
          pattern <- @forbidden_patterns,
          code =~ pattern do
        {path, inspect(pattern)}
      end

    assert offenders == [],
           "third-party catalog source reachable from the request path:\n" <>
             Enum.map_join(offenders, "\n", fn {p, pat} -> "  #{p} matched #{pat}" end)
  end

  test "positive control: the scanner detects synthetic violations" do
    js_synthetic = """
    // request-time enrichment
    const r = await fetch("https://vpic.nhtsa.dot.gov/api/vehicles/GetMakes");
    """

    ex_synthetic = """
    def enrich(vin), do: Req.get!("https://fueleconomy.gov/ws/rest/vehicle/menu/options")
    """

    js_matches =
      Enum.filter(@forbidden_patterns, fn p -> strip_comments(js_synthetic, ".js") =~ p end)

    ex_matches =
      Enum.filter(@forbidden_patterns, fn p -> strip_comments(ex_synthetic, ".ex") =~ p end)

    assert length(js_matches) >= 1
    assert length(ex_matches) >= 1
  end
end
