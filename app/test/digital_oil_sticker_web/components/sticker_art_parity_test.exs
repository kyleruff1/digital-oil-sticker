defmodule DigitalOilStickerWeb.Components.StickerArtParityTest do
  @moduledoc """
  The inline sticker artwork (StickerArt.artwork/1) is a transcription of
  `priv/static/images/dos-logo.svg`, and this file is what keeps the two from
  drifting. The default skin's pixel-parity rests on three legs:

    1. the inline markup's elements equal the file's, attribute for attribute
       (the permitted deltas — ids, classes, aria — are normalized away);
    2. the CSS token defaults equal the locked brand contract AND the values
       the file itself carries, so the stylesheet overrides resolve to the
       very numbers the presentation attributes already state;
    3. the new component ships no inline styles (CSP `style-src 'self'`,
       extending the sticker.ex-only ban).

  Together: attributes == file, CSS-that-outranks-attributes == same values,
  and no service-bay override block exists (asserted here too) — so the
  default skin renders exactly what the `<img>` used to.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Components.Sticker

  @svg_path Path.expand("../../../priv/static/images/dos-logo.svg", __DIR__)
  @art_path Path.expand(
              "../../../lib/digital_oil_sticker_web/components/sticker_art.ex",
              __DIR__
            )
  @css_path Path.expand("../../../assets/css/app.css", __DIR__)

  # The locked brand contract (docs/product/BRAND.md), as CSS token defaults.
  @locked_tokens %{
    "--skin-body" => "#FFFFFF",
    "--skin-body-opacity" => "0.72",
    "--skin-peel-opacity" => "0.82",
    "--skin-edge" => "#F7FAF8",
    "--skin-edge-opacity" => "0.94",
    "--skin-ink" => "#101820",
    "--skin-halo" => "#F7FAF8",
    "--skin-brand-a" => "#159447",
    "--skin-brand-b" => "#1769AA",
    "--skin-checker-light" => "#FFFFFF",
    "--skin-checker-dark" => "#101820",
    "--skin-vp-ink" => "#101820",
    "--skin-stamp" => "#159447",
    "--skin-stamp-underline" => "#15944766",
    "--skin-skeleton" => "#10182022"
  }

  # Attributes the transcription is allowed to add or drop (the permitted
  # deltas): identity/annotation attributes only, never paints or geometry.
  @ignored_attrs ~w(id class role focusable alt draggable)

  describe "structural parity with the reference SVG" do
    test "the inline artwork's elements equal the file's, in document order" do
      file_svg =
        @svg_path
        |> File.read!()
        |> LazyHTML.from_document()
        |> LazyHTML.query("svg")

      component_svg =
        render_component(&Sticker.sticker/1, %{})
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("svg")

      file_elements = @svg_path |> File.read!() |> tree_of() |> flatten()
      rendered_elements = render_component(&Sticker.sticker/1, %{}) |> tree_of() |> flatten()

      assert file_svg != [] and component_svg != [],
             "one of the two sides has no <svg> to compare"

      assert length(rendered_elements) == length(file_elements),
             "element count drifted: file has #{length(file_elements)}, " <>
               "inline artwork has #{length(rendered_elements)}"

      for {{file_el, rendered_el}, index} <-
            Enum.with_index(Enum.zip(file_elements, rendered_elements)) do
        assert rendered_el == file_el,
               "element ##{index} drifted from the reference SVG:\n" <>
                 "  file:      #{inspect(file_el)}\n" <>
                 "  component: #{inspect(rendered_el)}"
      end
    end
  end

  describe "token-default parity with the locked contract" do
    test "every --skin-* default in app.css equals the locked brand contract" do
      block = frame_block()

      declared =
        Regex.scan(~r/(--skin-[\w-]+):\s*([^;]+);/, block, capture: :all_but_first)
        |> Map.new(fn [k, v] -> {k, String.trim(v)} end)

      assert declared == @locked_tokens,
             "the .dos-sticker-frame token defaults drifted from the locked contract"
    end

    test "the CSS body/edge defaults equal the values the reference SVG itself carries" do
      # The contract tracks the FILE, not a copy: pull the cling-body rect's
      # paints straight out of dos-logo.svg and hold the CSS defaults to them.
      svg = File.read!(@svg_path)

      [body_rect] =
        Regex.run(~r/<rect[^>]*width="1128"[^>]*fill-opacity[^>]*\/>/, svg)
        |> List.wrap()

      assert attr_of(body_rect, "fill") == @locked_tokens["--skin-body"]

      assert normalize_number(attr_of(body_rect, "fill-opacity")) ==
               @locked_tokens["--skin-body-opacity"]

      assert attr_of(body_rect, "stroke") == @locked_tokens["--skin-edge"]

      assert normalize_number(attr_of(body_rect, "stroke-opacity")) ==
               @locked_tokens["--skin-edge-opacity"]
    end

    test "no service-bay override block exists — absence is the parity guarantee" do
      css = File.read!(@css_path)

      refute css =~ ~r/\[data-skin=["']?service-bay/,
             "a [data-skin=\"service-bay\"] block exists — the default skin must be " <>
               "the token defaults alone, or parity with the reference SVG is no longer " <>
               "guaranteed by construction"
    end
  end

  describe "CSP hygiene" do
    test "sticker_art.ex carries no inline style attributes" do
      art = File.read!(@art_path)

      refute art =~ ~r/style="/,
             "the artwork uses inline style attributes, which style-src 'self' refuses"

      refute art =~ ~r/style=\{/,
             "the artwork uses a dynamic inline style attribute, which style-src 'self' refuses"
    end
  end

  # -- comparison plumbing -----------------------------------------------------

  defp tree_of(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("svg")
    |> LazyHTML.to_tree()
  end

  # Depth-first flatten of the LazyHTML tree into comparable
  # {tag, attrs, own_text} triples. Both sides pass through the same parser,
  # so any parser-level attribute normalization applies equally to each.
  defp flatten(tree) when is_list(tree) do
    Enum.flat_map(tree, &flatten_node/1)
  end

  defp flatten_node({tag, attrs, children}) when tag in ["title", "desc"] and is_list(attrs) do
    # The transcription drops the file's accessible-name pair on purpose: the
    # inline artwork is aria-hidden decoration behind HTML overlays.
    _ = children
    []
  end

  defp flatten_node({tag, attrs, children}) when is_list(attrs) do
    own_text =
      children
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
      |> String.split()
      |> Enum.join(" ")

    [{tag, normalize_attrs(attrs), own_text} | flatten(children)]
  end

  # Text nodes and comments are not elements; own-text is captured by the
  # parent element above.
  defp flatten_node(_), do: []

  defp normalize_attrs(attrs) do
    attrs
    |> Enum.reject(fn {name, _} ->
      # `phx-r`/`data-phx-*` are LiveView's own test-render annotations, not
      # part of the artwork.
      name in @ignored_attrs or String.starts_with?(name, "aria-") or
        String.starts_with?(name, "phx-") or String.starts_with?(name, "data-phx")
    end)
    |> Enum.map(fn {name, value} ->
      value =
        value
        |> String.replace("url(#dos-art-duotone)", "url(#duotone)")
        |> String.replace("url(#dos-art-checkers)", "url(#flag-checkers)")

      {name, value}
    end)
    |> Enum.sort()
  end

  defp frame_block do
    css = File.read!(@css_path)

    case Regex.run(~r/\.dos-sticker-frame\s*\{([^}]*)\}/, css, capture: :all_but_first) do
      [block] -> block
      _ -> flunk("app.css has no .dos-sticker-frame token block")
    end
  end

  defp attr_of(element_source, name) do
    case Regex.run(~r/#{name}="([^"]*)"/, element_source, capture: :all_but_first) do
      [value] -> value
      _ -> flunk("the reference SVG's card rect carries no #{name} attribute")
    end
  end

  # ".72" (SVG idiom) and "0.72" (CSS idiom) are the same number.
  defp normalize_number("." <> rest), do: "0." <> rest
  defp normalize_number(value), do: value
end
