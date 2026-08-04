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

  # DOS-M09-003 AC-3 (strengthened): framing phrases the storage-state
  # bodies (empty / data_missing / storage_unavailable) are ALLOWED to
  # share verbatim across two or more bodies. The stricter 15-char shared-
  # substring pass below fails on any 15+ char slice reused across two
  # bodies unless the slice is contained in one of these entries. Keep
  # this list minimal — its purpose is to permit the domain vocabulary
  # ("this is a browser-only app, there is no server copy") without
  # permitting reused explanatory sentences that would blur the states.
  @shared_framing_whitelist [
    "stored in this browser",
    "no copy on our server",
    "on our server",
    "There is no account",
    "browser's site data"
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

  # DOS-M09-003 AC-3: the three storage-state bodies (empty, data_missing,
  # storage_unavailable) drive different user actions and must not blur into
  # each other. Cross-refutes on the headings are already enforced by the
  # hydration/state LiveView tests; this lints the prose bodies for two
  # distinctness properties.
  test "storage-state body prose is distinct across empty / data_missing / storage_unavailable" do
    alias DigitalOilStickerWeb.Copy

    bodies = [
      {:empty_body, Copy.empty_body()},
      {:data_missing_body, Copy.data_missing_body()},
      {:storage_unavailable_body, Copy.storage_unavailable_body()}
    ]

    # (a) No substring of length >= 40 chars appears in more than one body.
    # 40 chars is well above the shared framing phrases we expect to repeat
    # ("stored in this browser", "no copy on our server") but small enough
    # to catch a whole reused sentence or clause between states.
    window = 40

    for {name_a, body_a} <- bodies,
        {name_b, body_b} <- bodies,
        name_a != name_b,
        i <- 0..(String.length(body_a) - window)//1 do
      slice = String.slice(body_a, i, window)

      refute String.contains?(body_b, slice),
             "#{name_a} shares a #{window}-char substring with #{name_b}: #{inspect(slice)}"
    end

    # (b) Every body contributes at least one whole sentence that does not
    # appear as a substring of either other body — proves the states are
    # not near-duplicates dressed differently.
    for {name, body} <- bodies do
      sentences =
        body
        |> String.split(~r/(?<=[.!?])\s+/, trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      others =
        bodies
        |> Enum.reject(fn {n, _} -> n == name end)
        |> Enum.map(fn {_, b} -> b end)

      assert Enum.any?(sentences, fn s ->
               Enum.all?(others, fn other -> not String.contains?(other, s) end)
             end),
             "#{name} has no sentence unique to it"
    end
  end

  describe "storage-state body prose: stricter shared-fragment lint (AC-3)" do
    # The 40-char pass above catches whole reused sentences or clauses,
    # but it silently allows short shared fallbacks — the verify pass
    # flagged e.g. "Please refresh and try again." (28 chars) tacked on
    # to all three bodies as a case the 40-char window would miss. This
    # stricter pass slides a 15-char window and requires that any 15+ char
    # substring shared across two bodies is contained in one of the
    # framing phrases we EXPECT to repeat (@shared_framing_whitelist).
    test "no un-whitelisted 15-char substring is shared across two bodies" do
      alias DigitalOilStickerWeb.Copy

      # Remove every whitelisted framing phrase from each body BEFORE sliding
      # the 15-char window. A whitelisted phrase permits BOTH itself and any
      # of its own substrings to appear in multiple bodies — a naive per-slice
      # whitelist check misses this because a 15-char slice of a longer
      # whitelisted phrase (e.g. "re stored in th" out of "are stored in this
      # browser") isn't the whitelisted phrase itself. Stripping the phrases
      # up front is cleaner than per-slice recomputation.
      strip_whitelist = fn body ->
        Enum.reduce(@shared_framing_whitelist, body, fn allowed, acc ->
          String.replace(acc, allowed, " ")
        end)
      end

      bodies = [
        {:empty_body, strip_whitelist.(Copy.empty_body())},
        {:data_missing_body, strip_whitelist.(Copy.data_missing_body())},
        {:storage_unavailable_body, strip_whitelist.(Copy.storage_unavailable_body())}
      ]

      window = 15

      for {name_a, body_a} <- bodies,
          {name_b, body_b} <- bodies,
          name_a != name_b,
          i <- 0..(String.length(body_a) - window)//1 do
        slice = String.slice(body_a, i, window)

        # Skip slices that are all whitespace/punctuation — those aren't
        # meaningful shared content, they're just the connective tissue
        # between removed whitelisted phrases.
        meaningful? = String.match?(slice, ~r/[A-Za-z]{5,}/)

        if meaningful? and String.contains?(body_b, slice) do
          flunk(
            "#{name_a} shares a #{window}-char substring with #{name_b} " <>
              "outside the whitelisted framing phrases: #{inspect(slice)}"
          )
        end
      end
    end
  end

  test "no third-party logo or certification-mark assets ship" do
    images = Path.wildcard("priv/static/images/*")

    for path <- images do
      name = Path.basename(path) |> String.downcase()

      refute name =~
               ~r/(api[-_]?donut|starburst|shield|mobil|castrol|valvoline|pennzoil|toyota|ford[-_]logo|honda)/,
             "suspicious third-party mark asset: #{path}"
    end
  end
end
