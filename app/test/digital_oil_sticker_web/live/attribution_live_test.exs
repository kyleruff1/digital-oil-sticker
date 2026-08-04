defmodule DigitalOilStickerWeb.AttributionLiveTest do
  @moduledoc """
  DOS-M09-010 AC-10 — the /attribution page renders the policy-mandated
  no-affiliation statement and, for every `data_sources` row the catalog
  was compiled from, the provider, dataset name, the provider's own
  attribution string, the retrieval date, and the six FACTUAL_USE_AND_MARKS
  disposition axes.

  The catalog is a read-only fixture (no sandbox); the test asserts against
  whatever `Provenance.all_sources/0` returns from that fixture rather than
  hard-coding source rows, so adding sources to the fixture in a later
  milestone does not silently break this test.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.Catalog.Queries.Provenance
  alias DigitalOilStickerWeb.Copy

  # The six disposition axes, mapped from the visible <dt> label to the
  # `Provenance.all_sources/0` field the paired <dd> is supposed to render.
  # This mapping is the whole point of AC-10: a bare `html =~ value` sweep
  # would still pass if the template swapped, e.g., `copyright_basis` and
  # `review_status`, because both values still appear in the doc — just
  # under the wrong labels. Anchoring every value to its own label catches
  # that regression.
  @axis_label_to_field %{
    "Copyright basis:" => :copyright_basis,
    "Acquisition basis:" => :acquisition_basis,
    "Redistribution basis:" => :redistribution_basis,
    "Trademark posture:" => :trademark_posture,
    "Claim posture:" => :claim_posture,
    "Review status:" => :review_status
  }

  test "the no-affiliation statement renders at the top of /attribution", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/attribution")

    # The mandated statement (verbatim, per FACTUAL_USE_AND_MARKS_POLICY.md
    # §"No-affiliation statement"). Assert on a substring stable across
    # HEEx entity escaping.
    assert html =~ "Vehicle, lubricant, and filter names are used only to identify"

    # And it is anchored at the top of the page, above the sources list:
    # the disclosure must be seen before any source card is read.
    no_aff = Copy.no_affiliation() |> String.slice(0, 40)
    [before_list, _after_list] = String.split(html, "sources-list", parts: 2)

    assert String.contains?(before_list, no_aff),
           "expected Copy.no_affiliation() to render above the sources list on /attribution"
  end

  test "each source in Provenance.all_sources/0 renders with provider, attribution, and retrieval date",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/attribution")

    sources = Provenance.all_sources()

    assert sources != [],
           "the test fixture has no data_sources rows — /attribution has nothing to render"

    doc = LazyHTML.from_document(html)

    for s <- sources do
      assert html =~ s.provider,
             "expected provider #{inspect(s.provider)} to render for source #{s.id}"

      assert html =~ s.dataset_name,
             "expected dataset_name #{inspect(s.dataset_name)} for source #{s.id}"

      # Whichever attribution string the source carries — web_attribution_text
      # (short-form, nullable) is preferred when non-empty, otherwise
      # attribution_text (long-form, NOT NULL). Mirrors AttributionLive's
      # attribution_text/1 helper.
      expected_attribution =
        case s.web_attribution_text do
          t when is_binary(t) and t != "" -> t
          _ -> s.attribution_text
        end

      assert html =~ expected_attribution,
             "expected attribution string for source #{s.id} to render"

      # retrieved_at is nullable in schema.sql, so only assert on it when the
      # fixture actually carries one.
      if is_binary(s.retrieved_at) and s.retrieved_at != "" do
        # Assert on an independently-constructed "As of <date>" string rather
        # than through `Copy.as_of/1`. Both the LiveView and the previous test
        # version called that helper, so a change to `Copy.as_of/1` would drag
        # both sides in lockstep — nothing would fail even if the retrieval
        # date stopped reaching the surface. Recomputing the expected user-
        # visible string here decouples the test from the helper the template
        # uses and asserts on the visible surface directly.
        expected_as_of = "As of " <> s.retrieved_at

        retrieved_at_text = source_card_text(doc, s.id, "source-retrieved-at")

        assert retrieved_at_text != nil,
               "expected the source-retrieved-at paragraph to render for source #{s.id} because retrieved_at is #{inspect(s.retrieved_at)}"

        assert retrieved_at_text == expected_as_of,
               "expected the As-of paragraph for source #{s.id} to read #{inspect(expected_as_of)}, got #{inspect(retrieved_at_text)}"

        # And the raw date value must be substring-visible in that same
        # paragraph — if the template ever reformats the date, this catches
        # the case where the formatted string no longer contains the value
        # a reader would recognize.
        assert String.contains?(retrieved_at_text, s.retrieved_at),
               "expected retrieved_at #{inspect(s.retrieved_at)} to appear inside the As-of paragraph for source #{s.id}, got #{inspect(retrieved_at_text)}"
      end

      # The canonical_url renders as an <a href=...>, not just as text, so
      # the link is actually clickable — assert on the href attribute.
      assert html =~ ~s(href="#{s.canonical_url}"),
             "expected canonical_url #{s.canonical_url} to render as a link for source #{s.id}"

      # Extract the {label -> value} pairs from this card's disposition
      # block, then assert each of the six axes renders with the value from
      # the correct source field. Swapping any two axes in the template
      # would trip this — a bare substring loop would not.
      dispositions = source_card_dispositions(doc, s.id)

      for {label, field} <- @axis_label_to_field do
        expected_value = Map.fetch!(s, field)

        assert Map.get(dispositions, label) == expected_value,
               "expected #{label} to render with #{inspect(expected_value)} for source #{s.id}, got #{inspect(Map.get(dispositions, label))} (all pairs on this card: #{inspect(dispositions)})"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # LazyHTML helpers — the source-card templating puts each source inside a
  # `<li data-test="source-card" data-source-id="…">`, so we can scope every
  # per-source assertion to just that card and never confuse two sources.
  # ---------------------------------------------------------------------------

  # Extract the trimmed text of a specific data-test node inside the source
  # card matching `source_id`. Returns nil when the card or paragraph isn't
  # present (retrieved-at renders conditionally, so absence is meaningful).
  defp source_card_text(doc, source_id, data_test) do
    selector =
      ~s([data-test="source-card"][data-source-id="#{source_id}"] [data-test="#{data_test}"])

    case doc |> LazyHTML.query(selector) |> Enum.to_list() do
      [] -> nil
      [elem | _] -> elem |> LazyHTML.text() |> String.trim()
    end
  end

  # Extract a {label -> value} map from the six-axis disposition block for
  # the source card matching `source_id`. Labels come from `<dt>`, values
  # from the paired `<dd>`. Zipping preserves document order, which is the
  # order the template emits `<dt>` and `<dd>` in.
  defp source_card_dispositions(doc, source_id) do
    card_scope =
      ~s([data-test="source-card"][data-source-id="#{source_id}"] [data-test="source-dispositions"])

    dts = doc |> LazyHTML.query(card_scope <> " dt") |> Enum.to_list()
    dds = doc |> LazyHTML.query(card_scope <> " dd") |> Enum.to_list()

    Enum.zip(dts, dds)
    |> Map.new(fn {dt, dd} ->
      {dt |> LazyHTML.text() |> String.trim(), dd |> LazyHTML.text() |> String.trim()}
    end)
  end
end
