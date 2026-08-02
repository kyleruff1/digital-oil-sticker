defmodule DigitalOilStickerWeb.Components.StickerGeometryTest do
  @moduledoc """
  The sticker's viewports must sit inside the printable card.

  The defect this guards was found on a real Android tablet, not in review: the
  GRADE viewport was placed at `top:72% height:8%`, spanning 72–80% of the
  artwork, while the white card body ends at 75.6%. The label rendered inside
  the card and the value rendered below it, where it was clipped — so the
  sticker showed "GRADE" with no grade under it.

  These assertions read the geometry out of the component and out of the SVG,
  so a percentage that pushes content off the card fails here rather than on
  someone's screen.
  """
  use ExUnit.Case, async: true

  @component Path.expand("../../../lib/digital_oil_sticker_web/components/sticker.ex", __DIR__)
  @svg Path.expand("../../../priv/static/images/dos-logo.svg", __DIR__)
  @view_box_height 640

  # The artwork's white card body. Derived from the SVG rather than hardcoded,
  # so replacing the art moves the bound instead of silently invalidating it.
  defp card_bounds do
    [y, h] =
      @svg
      |> File.read!()
      |> then(
        &Regex.run(~r/<rect[^>]*y="(\d+)"[^>]*width="1128"[^>]*height="(\d+)"/, &1,
          capture: :all_but_first
        )
      )
      |> Enum.map(&String.to_integer/1)

    {y / @view_box_height * 100, (y + h) / @view_box_height * 100}
  end

  defp viewports do
    @component
    |> File.read!()
    |> then(
      &Regex.scan(
        ~r/top:([\d.]+)%;\s*width:[\d.]+%;\s*height:([\d.]+)%;"\s*\n\s*test_id="([\w-]+)"/,
        &1
      )
    )
    |> Enum.map(fn [_, top, height, id] ->
      {id, parse_percent(top), parse_percent(height)}
    end)
  end

  defp parse_percent(value) do
    {number, _} = Float.parse(value)
    number
  end

  test "the artwork still declares a card body we can bound against" do
    {top, bottom} = card_bounds()

    assert top > 0 and bottom > top
    assert_in_delta bottom, 75.6, 0.1
  end

  test "every viewport is fully inside the printable card" do
    {card_top, card_bottom} = card_bounds()
    found = viewports()

    assert length(found) == 4, "expected four viewports, found #{length(found)}"

    for {id, top, height} <- found do
      assert top >= card_top,
             "#{id} starts at #{top}%, above the card's top edge (#{card_top}%)"

      assert top + height <= card_bottom,
             "#{id} ends at #{top + height}%, past the card's bottom edge (#{card_bottom}%) — " <>
               "its value renders outside the sticker and is clipped"
    end
  end

  test "the grade viewport is as tall as the others, since it carries the same content" do
    heights = viewports() |> Map.new(fn {id, _top, h} -> {id, h} end)

    assert heights["sticker-grade"] == heights["sticker-date"],
           "grade got #{heights["sticker-grade"]}% for the same label+value stack " <>
             "the other viewports get #{heights["sticker-date"]}% for"
  end

  test "the sticker declares a container, so its cqw text scales with the sticker" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    component = File.read!(@component)

    # Without container-type, `cqw` resolves against the VIEWPORT, so the text
    # grows with the window while the sticker does not. That is how the grade
    # value ended up 20% larger than its box on an 800px-wide tablet.
    assert component =~ "cqw", "the component no longer uses container units; this test can go"

    assert css =~ ~r/\.dos-sticker\s*\{[^}]*container-type:\s*inline-size/s,
           "the sticker uses cqw units but declares no container, so they resolve against the viewport"
  end
end
