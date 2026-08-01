defmodule DigitalOilStickerWeb.CopyLintTest do
  @moduledoc """
  The copy-lint gate: prohibited storage-framing and claim-language terms
  fail the build anywhere in the copy catalog, LiveViews, or components;
  the mandated strings must exist verbatim in the copy catalog.
  """
  use ExUnit.Case, async: true

  @prohibited [
    # storage framing (INV-25 / ADR-0004)
    "saved to your account",
    "synced",
    "backed up",
    # claim language (rev-2 policy)
    "best oil",
    "guaranteed",
    "warranty safe",
    "manufacturer approved",
    "API approved",
    "recommended by",
    "works with every"
  ]

  # "restore" appears in legitimate words (e.g. "restored" in code identifiers);
  # lint the copy surface for the standalone user-facing phrase.
  @prohibited_copy_only ["restore your", "restore from", "we'll remember"]

  @mandated [
    "Not specified",
    "Exact configuration not verified",
    "Source unavailable",
    "Your interval",
    "Meets the recorded requirements",
    "Estimated due date",
    "Not saved to this browser",
    "Reloaded from this browser's newer data",
    "Could not read some records",
    "stored in this browser"
  ]

  defp surface_files do
    Path.wildcard("lib/digital_oil_sticker_web/**/*.ex") ++
      Path.wildcard("lib/digital_oil_sticker_web/**/*.heex")
  end

  test "prohibited terms appear nowhere in the web surface" do
    for file <- surface_files(), content = File.read!(file), term <- @prohibited do
      refute String.contains?(String.downcase(content), String.downcase(term)),
             "#{file} contains prohibited term: #{term}"
    end
  end

  test "prohibited copy-only phrases appear nowhere in the copy catalog" do
    content = File.read!("lib/digital_oil_sticker_web/copy.ex") |> String.downcase()

    for term <- @prohibited_copy_only do
      refute String.contains?(content, term), "copy.ex contains prohibited phrase: #{term}"
    end
  end

  test "mandated strings exist verbatim in the copy catalog" do
    content = File.read!("lib/digital_oil_sticker_web/copy.ex")

    for phrase <- @mandated do
      assert String.contains?(content, phrase), "copy.ex is missing mandated string: #{phrase}"
    end
  end

  test "no third-party logo or certification-mark assets ship" do
    images = Path.wildcard("priv/static/images/*")

    for path <- images do
      name = Path.basename(path) |> String.downcase()

      refute name =~ ~r/(api[-_]?donut|starburst|shield|mobil|castrol|valvoline|pennzoil|toyota|ford[-_]logo|honda)/,
             "suspicious third-party mark asset: #{path}"
    end
  end
end
