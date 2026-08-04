defmodule DigitalOilStickerWeb.SessionOnlyBannerTest do
  @moduledoc """
  DOS-M09-003 AC-6: in session-only mode the export affordance is present at
  first render and the banner cannot be dismissed (INV-5, INV-25).

  The specification is emphatic: session-only mode gets a **persistent,
  non-dismissible** banner stating that nothing is being saved (FR-8). The
  two failures this test guards against are exactly the two shapes that
  wording rules out:

    1. The banner rendered as a flash (dismissible via `lv:clear-flash`) —
       the user taps it away and keeps entering data that will not survive
       the tab closing, defeating INV-24.6 and INV-25 in one click.
    2. The banner cleared by any event handler on the page — a mutation
       attempt that only put_flashes it fresh, or a re-render that lets it
       drop off. Persistence must be intrinsic to the mode, not incidental
       to whichever event last fired.

  The current codebase raises `session_only` through `put_flash/3` in the
  individual LiveViews (see `sticker_live.ex`, `oil_change_live.ex`,
  `history_live.ex`, `vehicle_profile_live.ex`), which IS dismissible via
  the flash component's outer-div `lv:clear-flash` handler. The banner-move
  (referred to in DOS-M09-003 planning as the G11 code slice) is expected
  to land the banner in `Layouts.app` gated on `storage_mode == :session_only`,
  parallel to the `:if={@read_only}` and `:if={@conflict_notice}` blocks
  already there. This test is written to that expected behavior; it will
  fail red until the layout wiring lands, which is the point.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Apostrophe-safe substring of Copy.session_only_banner():
  #   "Nothing is being stored in this browser. This browser is not letting
  #    the app store data — ..."
  # HEEx escapes `'` to `&#39;`, but there are no apostrophes in this
  # opening phrase, so the raw substring survives rendering unchanged.
  # (Matches the pattern used in storage_recovery_test.exs — "stored
  # records are gone" — for the same reason.)
  @banner_substring "Nothing is being stored in this browser"

  defp hydrate_session_only(view) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 0,
      "tab_id" => "t",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" => %{
        "meta" => nil,
        "vehicles" => [],
        "events" => [],
        "readings" => [],
        "usage" => [],
        "reminders" => [],
        "prefs" => nil
      },
      "storage" => %{"mode" => "session_only", "reason" => "unavailable"}
    })
  end

  test "renders the persistent session-only banner at first render, with export offered inline",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    html = hydrate_session_only(view)

    # (a) Stable DOM hook that other surfaces (tests, screenshots, docs) can
    # anchor on without depending on classnames or copy churn.
    assert html =~ ~s(data-test="session-only-banner"),
           "session-only banner missing from first render after session_only hydrate — " <>
             "layout should render the banner gated on storage_mode == :session_only " <>
             "(FR-8, DOS-M09-003 AC-6)."

    # (b) The mandated copy is present, verbatim (via an apostrophe-safe
    # substring). Copy.session_only_banner() is the required text per the
    # copy catalog; the copy-lint gate already guards its presence in the
    # module, this asserts it reaches the rendered layout.
    assert html =~ @banner_substring

    # (c) The export affordance is in the SAME rendered output — FR-10
    # requires export to be prominent and repeatedly offered in session-only
    # mode, and the banner is the anchor for it. "Export a file" is the
    # wording used by every other persistent banner in Layouts.app
    # (read-only, unsaved-writes) so users see one consistent affordance.
    assert html =~ "Export a file"

    # (d) But "Export a file" appearing anywhere on the page is not enough:
    # the affordance has to be INSIDE the banner element, not incidentally
    # rendered by an empty-state or hydration-refused block that only some
    # views produce. Scope the assertion to `[data-test="session-only-banner"]
    # a` and require an anchor with that copy nested inside the banner div.
    # `element/3` with a text filter raises if no such element exists, so
    # `render/1` doubles as the assertion — and the follow-up substring
    # match is a defensive belt-and-braces sanity check.
    banner_export_html =
      view
      |> element(~s([data-test="session-only-banner"] a), "Export a file")
      |> render()

    assert banner_export_html =~ "Export a file",
           "Export a file link is not nested inside the session-only banner — " <>
             "the affordance must be co-located with the notice, not merely " <>
             "appearing somewhere else on the page (FR-10, DOS-M09-003 AC-6)."
  end

  test "the banner is NOT wrapped in a dismissible flash", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    html = hydrate_session_only(view)

    # Stronger check FIRST, evaluated on the element block itself: no
    # `phx-click=` attribute of ANY kind may appear inside the banner div,
    # not just `lv:clear-flash`. A regression that added
    # `phx-click={JS.push("dismiss_session_banner")}` (or any other custom
    # dismiss handler) would slip past the `lv:clear-flash` window check
    # below but is caught here — the banner element as rendered has no
    # click handler at all, on the div or on any descendant. Element
    # extraction is done via LiveViewTest's `element/2 |> render/1`, which
    # returns the outer HTML of the matched element only, so no adjacent
    # markup pollutes the substring search.
    banner_html =
      view
      |> element(~s([data-test="session-only-banner"]))
      |> render()

    refute banner_html =~ "phx-click=",
           "session-only banner element carries a phx-click= attribute on " <>
             "itself or a descendant — the banner must be persistent and " <>
             "non-dismissible, with no click-driven exit path. Any custom " <>
             "dismiss handler (JS.push(...), JS.hide(...), etc.) is a " <>
             "regression against FR-8 / INV-25 / DOS-M09-003 AC-6."

    # A dismissible flash toast carries the `lv:clear-flash` push on its
    # outer div (see core_components.ex flash/1); rendered by Phoenix, the
    # event name appears in the phx-click attribute value (JSON-encoded
    # from `JS.push("lv:clear-flash", ...)`). Whichever exact serialisation
    # Phoenix emits, the literal substring `lv:clear-flash` is present in
    # the HTML wherever a flash is dismissible.
    #
    # Look up a window on both sides of the banner element and refute
    # that substring anywhere in the neighbourhood — the "lookahead-style"
    # check the AC calls for. 400 chars on each side is well beyond the
    # size of any single alert container (flash toast is ~200 chars of
    # markup including the icon and close button) so a dismissible wrapper
    # around this element cannot hide from the window.
    case String.split(html, "session-only-banner", parts: 2) do
      [before_marker, after_marker] ->
        window_before =
          String.slice(before_marker, max(0, String.length(before_marker) - 400)..-1//1)

        window_after = String.slice(after_marker, 0, 400)
        neighbourhood = window_before <> window_after

        refute neighbourhood =~ "lv:clear-flash",
               "session-only banner appears to be dismissible — `lv:clear-flash` " <>
                 "found within 400 chars of the session-only-banner element. The " <>
                 "banner must be a persistent layout notice, not a flash toast " <>
                 "(FR-8, DOS-M09-003 AC-6)."

        # And separately the exact string the AC calls out, in case a future
        # framework version emits the phx-click attribute unescaped.
        refute neighbourhood =~ ~s(phx-click="lv:clear-flash")

      _ ->
        flunk(
          "session-only-banner element missing from HTML; cannot check dismissibility. " <>
            "Ensure the layout renders it before running this assertion."
        )
    end
  end

  test "the banner survives an interaction attempt that is a no-op in session_only mode",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    hydrate_session_only(view)

    # `switch_vehicle` is refused by Session.mutations_enabled?/1 when
    # storage_mode == :session_only (see StickerLive.handle_event/3). Firing
    # the event exercises the code path a user would trip if they somehow
    # reached the switcher control. Whatever the handler does — put_flash
    # today, no-op after the banner move, or something else — the persistent
    # session-only banner must still be in the DOM afterwards. That is what
    # "persistent, non-dismissible" MEANS in practice: no event on this page
    # can make it go away.
    _ = render_click(view, "switch_vehicle", %{"vehicle-id" => "no-such-vehicle"})

    html = render(view)

    assert html =~ ~s(data-test="session-only-banner"),
           "session-only banner disappeared after a no-op mutation attempt — " <>
             "the banner must persist for the lifetime of the session_only mode, " <>
             "not be cleared by any event handler (FR-8, DOS-M09-003 AC-6)."

    assert html =~ @banner_substring

    # And the Export CTA has to still be OFFERED — "re-offered after each
    # meaningful entry" (FR-10) means the affordance is not consumed by the
    # interaction: after a mutation attempt the user must still see the same
    # inline exit path they saw at first render. Scope the check to the
    # banner element so an "Export a file" link elsewhere on the page
    # (empty-state block, hydration-refused block) cannot mask a regression
    # that stripped the CTA from the banner itself.
    banner_export_after =
      view
      |> element(~s([data-test="session-only-banner"] a), "Export a file")
      |> render()

    assert banner_export_after =~ "Export a file",
           "Export a file link vanished from the session-only banner after a " <>
             "mutation attempt — FR-10 requires the export affordance to be " <>
             "re-offered after every meaningful entry, not consumed by the " <>
             "first interaction (DOS-M09-003 AC-6)."
  end
end
