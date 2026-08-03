defmodule DigitalOilSticker.NoPersonalEctoSchemaTest do
  @moduledoc """
  M01-003 AC-7 and FR-3: no module under `DigitalOilSticker.*` defines a
  personal-data Ecto schema. There is no `UserRepo`. The catalog is served
  from `CatalogRepo` via schemaless `Ecto.Query` selects; no code path holds
  an `Ecto.Schema` for a personal-data table because no such table exists.

  Enforcement rather than convention. A well-meaning contributor adding a
  `use Ecto.Schema` module — a session store, an anonymous-ID table, a
  push-subscription table, a "just for logging" audit table — trips this test
  before it can reach review.
  """
  use ExUnit.Case, async: true

  @app_root Path.expand("../..", __DIR__)
  @domain_root Path.join(@app_root, "lib/digital_oil_sticker")

  defp elixir_sources do
    @domain_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      {Path.relative_to(path, @app_root),
       path |> File.read!() |> String.replace("\r\n", "\n")}
    end)
  end

  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end

  test "no domain module uses Ecto.Schema" do
    sources = elixir_sources()
    assert length(sources) > 10, "no domain sources scanned — glob is broken"

    offenders =
      for {path, source} <- sources,
          code = strip_comments(source),
          code =~ ~r/\buse\s+Ecto\.Schema\b/,
          do: path

    assert offenders == [],
           "these modules declare an Ecto schema: #{Enum.join(offenders, ", ")}"
  end

  test "no module named *UserRepo exists in the tree" do
    offenders =
      for {path, source} <- elixir_sources(),
          code = strip_comments(source),
          code =~ ~r/\bdefmodule\s+[\w\.]*UserRepo\b/,
          do: path

    assert offenders == [],
           "a UserRepo module was introduced: #{Enum.join(offenders, ", ")}"
  end

  test "positive control: the scanners detect synthetic violations" do
    schema_synthetic = """
    defmodule DigitalOilSticker.Personal.Session do
      use Ecto.Schema
      schema "sessions" do
        field :token, :string
      end
    end
    """

    repo_synthetic = """
    defmodule DigitalOilSticker.UserRepo do
      use Ecto.Repo, otp_app: :digital_oil_sticker
    end
    """

    assert schema_synthetic =~ ~r/\buse\s+Ecto\.Schema\b/
    assert repo_synthetic =~ ~r/\bdefmodule\s+[\w\.]*UserRepo\b/
  end
end
