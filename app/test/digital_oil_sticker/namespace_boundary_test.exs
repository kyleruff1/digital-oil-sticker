defmodule DigitalOilSticker.NamespaceBoundaryTest do
  @moduledoc """
  ADR-0004 §"Enforcement" bullet 2: no domain-namespace module references
  Phoenix.LiveView, Plug, or the web-layer protocol modules. The domain layer
  speaks to the outside world through ports (behaviours) and public APIs; the
  framework lives exclusively in the web layer.

  This is a source-level scan, not a BEAM-level one. Source is what a reviewer
  reads, and an `alias Phoenix.LiveView` in a domain module is the line that
  would import the coupling — catching it before compilation is the earlier gate.
  """
  use ExUnit.Case, async: true

  @app_root Path.expand("../..", __DIR__)
  @domain_root Path.join(@app_root, "lib/digital_oil_sticker")

  # Modules that are infrastructure, not domain logic. They are allowed to
  # reference framework modules because they wire the application together.
  @infrastructure_files ~w(application.ex release.ex catalog_repo.ex)

  defp domain_sources do
    @domain_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(fn path ->
      Path.basename(path) in @infrastructure_files
    end)
    |> Enum.map(fn path ->
      {Path.relative_to(path, @app_root), path |> File.read!() |> String.replace("\r\n", "\n")}
    end)
  end

  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end

  describe "domain modules are isolated from the web framework" do
    test "no domain module references Phoenix.LiveView" do
      sources = domain_sources()
      assert length(sources) > 15, "found only #{length(sources)} domain sources — glob is wrong"

      offenders =
        for {path, source} <- sources,
            code = strip_comments(source),
            code =~ ~r/\bPhoenix\.LiveView\b/,
            do: path

      assert offenders == [],
             "these domain modules reference Phoenix.LiveView: #{Enum.join(offenders, ", ")}"
    end

    test "no domain module references Plug" do
      offenders =
        for {path, source} <- domain_sources(),
            code = strip_comments(source),
            code =~ ~r/\bPlug\./,
            do: path

      assert offenders == [],
             "these domain modules reference Plug: #{Enum.join(offenders, ", ")}"
    end

    test "no domain module references the web layer" do
      offenders =
        for {path, source} <- domain_sources(),
            code = strip_comments(source),
            code =~ ~r/\bDigitalOilStickerWeb\b/,
            do: path

      assert offenders == [],
             "these domain modules reference the web layer: #{Enum.join(offenders, ", ")}"
    end

    test "no domain module other than CatalogRepo uses Ecto.Repo" do
      offenders =
        for {path, source} <- domain_sources(),
            code = strip_comments(source),
            code =~ ~r/\buse\s+Ecto\.Repo\b/,
            do: path

      assert offenders == [],
             "these domain modules declare a second Ecto.Repo: #{Enum.join(offenders, ", ")}"
    end

    test "the scanner has enough source files to be non-vacuous" do
      sources = domain_sources()
      assert length(sources) > 15

      has_catalog = Enum.any?(sources, fn {p, _} -> p =~ "catalog" end)
      has_local_store = Enum.any?(sources, fn {p, _} -> p =~ "local_store" end)
      has_clock = Enum.any?(sources, fn {p, _} -> p =~ "clock" end)

      assert has_catalog, "scanner missed the catalog modules"
      assert has_local_store, "scanner missed the local_store modules"
      assert has_clock, "scanner missed the clock module"
    end

    test "positive control: the scanner detects a violation in synthetic source" do
      synthetic = """
      defmodule DigitalOilSticker.Fake do
        import Phoenix.LiveView
        alias Plug.Conn
        alias DigitalOilStickerWeb.Router
      end
      """

      assert synthetic =~ ~r/\bPhoenix\.LiveView\b/
      assert synthetic =~ ~r/\bPlug\./
      assert synthetic =~ ~r/\bDigitalOilStickerWeb\b/
    end
  end
end
