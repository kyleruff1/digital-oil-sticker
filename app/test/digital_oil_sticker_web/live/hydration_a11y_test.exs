defmodule DigitalOilStickerWeb.HydrationA11yTest do
  @moduledoc """
  AC-18 headless subset: the live-region and focus-preservation contract
  that LiveViewTest can verify from the outside on the sticker route.

  A screen-reader user has no visual cue when hydration completes. Every
  state transition must land some announcement in DOM order — sr-only
  during :hydrating, then the visible heading/content after hydrate
  resolves — and every persistent layout banner (read-only,
  unsaved-writes, conflict-notice) must wear the role and aria-live
  combination assistive tech treats appropriately for that banner's
  intent.

  Contrast, zoom, and reflow are visual/CSS properties outside the
  headless surface and stay in the owner_only manual sweep. The
  invariants pinned here are the ones a routine LiveView render can
  silently regress:

    1. The :hydrating render carries an announcement carrier
       (Copy.sr_checking/0, since the sticker's :hydrating mode has no
       role=status region and would otherwise leave a screen reader
       silent).
    2. Hydrate lands the new state's own visible content in DOM order,
       and the layout's standing polite aria-live region (flash_group)
       remains available as a channel for later announcements.
    3. Each of the three layout banners renders with the accessible
       role/aria-live pair its intent demands: role=alert for the two
       act-now banners (read-only, unsaved-writes), role=status
       aria-live=polite for the conflict notice (informational — the
       app has already re-hydrated, the banner exists to EXPLAIN why
       the screen just changed).
    4. Nothing in the layout uses phx-mounted to steal focus on
       hydrate resolution. A JS.focus in phx-mounted fires every time
       the element is inserted; on hydrate that would yank focus off
       whatever the user was interacting with the moment the sticker
       skeleton is swapped for real content.

  HEEx escapes apostrophes to `&#39;`, so any assertion against Copy
  strings that contain them uses an apostrophe-free substring (same
  pattern as error_mapping_test.exs / hydration_wiring_test.exs).
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.LocalStore.Caps
  alias DigitalOilStickerWeb.Copy

  @car_one "11111111-1111-4111-8111-111111111111"

  # Default-shape envelope helper, mirroring storage_recovery_test's helper.
  # Callers merge shallow overrides; overriding "data" or "storage" replaces
  # the whole nested map (Map.merge/2 is shallow), so overrides for those
  # keys must supply every sub-key the assertion depends on. to_garage/1 in
  # Session defaults any missing collection to [] via Map.get/3, so leaving
  # out list keys in an override is fine when the test does not read them.
  defp hydrate(view, overrides) do
    render_hook(
      view,
      "local_store:hydrate",
      Map.merge(
        %{
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
          "storage" => %{"mode" => "idb", "boot_hint" => "never"}
        },
        overrides
      )
    )
  end

  # Pull the OPENING tag of the element with the given id out of rendered
  # HTML so per-element attributes can be asserted without falling over
  # attribute-order assumptions or matching a same-named attribute on some
  # OTHER element (aria-live="polite" also lives on the flash_group, so a
  # bare `html =~ ~s(aria-live="polite")` proves nothing about the banner
  # under test). Returns nil when the element is absent, which lets each
  # caller print its own "banner missing" failure message rather than a
  # cryptic MatchError.
  defp tag_for_id(html, id) do
    case Regex.run(~r/<[a-z][a-z0-9]*[^>]*\bid="#{id}"[^>]*>/i, html) do
      [tag] -> tag
      _ -> nil
    end
  end

  # An over-cap payload for the vehicles-count cap, so `Caps.check/2`
  # rejects with `{:error, {:cap_exceeded, :vehicles}}` and hydrate lands
  # in :hydration_refused. Mirrors the helper in storage_status_panel_test.
  defp too_many_vehicles do
    for i <- 1..(Caps.max_vehicles() + 1) do
      %{
        "vehicle_id" =>
          "1111111#{rem(i, 10)}-1111-4111-8111-#{String.pad_leading("#{i}", 12, "0")}",
        "archived" => false
      }
    end
  end

  describe "live-region contract across hydration" do
    test "the initial :hydrating render exposes a Copy.sr_checking announcement carrier",
         %{conn: conn} do
      {:ok, _view, hydrating_html} = live(conn, ~p"/")

      # The sticker's :hydrating branch renders skeleton viewports, each
      # of which carries an sr-only span with Copy.sr_checking/0. Without
      # this, a screen reader lands on the page mid-hydrate and hears
      # nothing — the visual skeleton is aria-hidden by design.
      assert hydrating_html =~ Copy.sr_checking(),
             "the :hydrating skeleton must carry Copy.sr_checking() so screen readers hear something while hydrate runs"

      # The layout's standing polite aria-live region (flash_group) is
      # already in DOM at this point — a channel that survives across
      # every state transition so future put_flash announcements land.
      assert hydrating_html =~ ~s(id="flash-group"),
             "flash_group must render on the :hydrating pass so its aria-live region exists from the start"

      assert hydrating_html =~ ~s(aria-live="polite"),
             "flash_group must be aria-live=polite from the :hydrating pass forward"
    end

    test "hydrate to :empty removes the sr_checking carrier and surfaces the empty-state heading",
         %{conn: conn} do
      {:ok, view, hydrating_html} = live(conn, ~p"/")

      # Pre-hydrate baseline: sr_checking is the announcement, the
      # empty-state heading is NOT yet a truthful claim.
      assert hydrating_html =~ Copy.sr_checking()
      refute hydrating_html =~ Copy.empty_heading()

      # Empty envelope (defaults: no records, boot_hint "never", meta
      # nil) resolves to :empty. See Session.resolve_state/2.
      after_hydrate = hydrate(view, %{})

      # (1) The transitional sr-only announcement must clear — a screen
      # reader that still saw "checking…" after hydrate settled would be
      # told the app is doing something it has already finished.
      refute after_hydrate =~ Copy.sr_checking(),
             "sr_checking must clear once hydrate resolves; otherwise screen readers still hear 'checking' after the state has settled"

      # (2) The new state's own visible heading appears in DOM order,
      # so a linear traversal announces the resolved state. This is the
      # "a different aria-live region announces the new state" half of
      # the contract — DOM-order content is what a screen reader
      # actually reads when it reaches this section.
      assert after_hydrate =~ Copy.empty_heading(),
             "hydrate to :empty must surface Copy.empty_heading() so screen readers announce the resolved state in DOM order"

      # (3) The standing polite aria-live region survives across the
      # transition, so subsequent flash-driven announcements still have
      # somewhere to land.
      assert after_hydrate =~ ~s(id="flash-group"),
             "flash_group must persist across hydrate resolution"

      assert after_hydrate =~ ~s(aria-live="polite"),
             "the polite aria-live region must persist across hydrate resolution"
    end
  end

  describe "layout banner accessibility roles" do
    test "read-only banner is role=alert (act-now: mutations are disabled)", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # newer_than_server -> read_only=true, :loaded. Same envelope
      # shape newer_schema_readonly_test uses.
      html =
        hydrate(view, %{
          "schema_version" => 99,
          "seq" => 5,
          "data" => %{"meta" => %{"schema_version" => 99, "seq" => 5}},
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      assert html =~ ~s(data-test="read-only"),
             "read_only=true must render the layout banner test hook"

      tag = tag_for_id(html, "read-only-notice")

      assert tag, "read-only-notice element must be in DOM once @read_only is true"

      # role=alert (not status) is deliberate: this browser holds data a
      # newer app version wrote, and every mutation is off. A polite
      # status announcement would under-signal that the user's writes are
      # not landing.
      assert tag =~ ~s(role="alert"),
             "read-only-notice must be role=alert — mutations are off; assistive tech must treat this as an act-now condition, not passive info"
    end

    test "unsaved-writes banner is role=alert (act-now: an entry the user sees is not stored)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # Land in a hydrated state so the layout renders normally; the
      # banner attaches once :unsaved_writes has an entry.
      hydrate(view, %{})

      # mark_unsaved/3 (called by handle_ack's error clause) uses
      # Map.update with a default, so a fake mutation_id still appends
      # to :unsaved_writes — no need to first stage a real mutation.
      # This keeps the test focused on the banner's a11y contract, not
      # on the mutation round-trip (covered by ack_failure_reasons_test).
      html =
        render_hook(view, "local_store:ack", %{
          "mutation_id" => "fake-mutation-id",
          "status" => "error",
          "reason" => "quota_exceeded"
        })

      assert html =~ ~s(data-test="unsaved-writes"),
             "a failed ack must render the unsaved-writes banner the test hook anchors on"

      tag = tag_for_id(html, "unsaved-writes")

      assert tag, "unsaved-writes element must be in DOM once :unsaved_writes is non-empty"

      # role=alert is the correct fit: "a record you believe is saved is
      # not saved" is an act-now condition that must interrupt normal
      # reading. INV-24.5 forbids dismissing or timing out this banner,
      # which is why polite/status would be inappropriate.
      assert tag =~ ~s(role="alert"),
             "unsaved-writes must be role=alert — a record the user believes is saved but is not is an act-now condition"
    end

    test "conflict-notice banner is role=status aria-live=polite (informational: reload already happened)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # Settle in :loaded so the conflict path has state to leave and
      # return to. Envelope shape mirrors two_tab_conflict_test.
      hydrate(view, %{
        "seq" => 1,
        "data" => %{
          "meta" => %{"schema_version" => 1, "seq" => 1},
          "vehicles" => [
            %{
              "vehicle_id" => @car_one,
              "nickname" => "Camry",
              "archived" => false
            }
          ],
          "events" => [],
          "readings" => [],
          "usage" => [],
          "reminders" => [],
          "prefs" => nil
        },
        "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
      })

      # A sibling tab wrote a newer seq. Session.handle_conflict/2 raises
      # :conflict_notice and re-enters :hydrating so mutations pause.
      html =
        render_hook(view, "local_store:conflict", %{
          "seq" => 2,
          "reason" => "stale_seq_cas_failed"
        })

      assert html =~ ~s(data-test="conflict-notice"),
             "conflict must render the layout banner test hook"

      tag = tag_for_id(html, "conflict-notice")

      assert tag, "conflict-notice element must be in DOM once :conflict_notice is true"

      # role=status + aria-live=polite is the M09-002 contract: the app
      # has already re-hydrated (state is truthful), and the banner
      # exists to EXPLAIN what the user just watched happen. role=alert
      # would over-signal and interrupt the user for something already
      # handled; polite lets the current utterance finish before the
      # announcement lands.
      assert tag =~ ~s(role="status"),
             "conflict-notice must be role=status — the reload already happened; the banner explains, it does not demand"

      assert tag =~ ~s(aria-live="polite"),
             "conflict-notice must be aria-live=polite — polite lets the user finish the current utterance before announcement"
    end

    test "session-only banner is role=alert (act-now: nothing the user types is being persisted)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # session_only storage mode is the AC-6 layout addition: the banner
      # is gated on @storage_mode == :session_only in Layouts.app and
      # renders on every hydrate that lands in that mode, parallel to
      # read-only / unsaved-writes / conflict-notice. Envelope shape
      # mirrors session_only_banner_test.
      html =
        hydrate(view, %{
          "storage" => %{"mode" => "session_only", "boot_hint" => "never"}
        })

      assert html =~ ~s(data-test="session-only-banner"),
             "session_only hydrate must render the layout banner test hook"

      tag = tag_for_id(html, "session-only-notice")

      assert tag,
             "session-only-notice element must be in DOM once @storage_mode is :session_only"

      # role=alert (not status) is the AC-6 contract: nothing the user
      # types is being persisted and the banner cannot be dismissed
      # (INV-24.6 / INV-25). polite/status would under-signal a
      # non-persistence condition the user has to act on — export the
      # data — before the tab closes and it is lost.
      assert tag =~ ~s(role="alert"),
             "session-only-notice must be role=alert — nothing is being persisted; assistive tech must treat this as an act-now condition, not passive info"
    end
  end

  describe "focus preservation across hydrate resolution" do
    # A phx-mounted={JS.focus(...)} attribute fires the moment its
    # element is inserted into DOM. On hydrate resolution the sticker
    # skeleton is swapped for real content, which would trigger any
    # such focus command and steal focus from whatever the user was
    # currently on (a form field mid-typing, the theme toggle, a link
    # they were tabbing through). `autofocus` is the HTML-level
    # equivalent: a boolean attribute the browser acts on the moment
    # the element is parsed into the document, so a newly rendered
    # element carrying it steals focus at hydrate resolution just the
    # same. LiveViewTest cannot directly observe focus in a headless
    # run, but it CAN observe both attributes — their absence across
    # every resolved state is what AC-18's focus-preservation clause
    # reduces to in a headless test.
    #
    # HEEx serialises JS commands as JSON in the rendered attribute:
    # `phx-mounted="[[&quot;focus&quot;,{...}]]"`. The phx-mounted
    # regex catches any such attribute whose value contains the
    # "focus" op slug, regardless of exact quoting or command wrapping.
    # The autofocus regex requires a whitespace boundary on the left
    # and one of {whitespace, `=`, `>`} on the right so it only fires
    # on the actual HTML attribute (not on a Copy string that happens
    # to contain the word).
    defp assert_no_focus_theft(html, state) do
      refute html =~ ~r/phx-mounted[^>]*focus/,
             "#{state} layout contains a phx-mounted focus command — hydrate resolution would steal focus"

      refute html =~ ~r/\sautofocus[\s=>]/,
             "#{state} layout contains an autofocus attribute — hydrate resolution would steal focus"
    end

    test "no layout element uses phx-mounted (or autofocus) to focus something on hydrate",
         %{conn: conn} do
      {:ok, view, hydrating_html} = live(conn, ~p"/")

      assert_no_focus_theft(hydrating_html, :hydrating)

      # :empty — empty envelope with defaults resolves to :empty via
      # Session.resolve_state/2, the original coverage this test opened
      # with. Kept as the first post-hydrate check so the pre-existing
      # regression path stays green.
      after_hydrate = hydrate(view, %{})
      assert_no_focus_theft(after_hydrate, :empty)
    end

    # Each of the four non-:hydrating resolutions is reached on its own
    # fresh mount because hydrate/2 fires the ONE hydrate this test
    # cares about; the layout must stay focus-safe on the render that
    # swaps the sticker skeleton for real content, and that only
    # happens on the first successful hydrate per mount. Every branch
    # runs the SAME assert_no_focus_theft helper — the invariant is
    # identical across states; the point is that no state is exempt.
    #
    # State-selection reference (Session.resolve_state/2 +
    # Session.handle_hydrate/2):
    #   :loaded              — populated envelope (vehicles present)
    #   :data_missing        — empty payload + storage boot_hint="has_data"
    #   :hydration_refused   — over-cap payload (cap_exceeded)
    #   :storage_unavailable — session_only storage mode

    test "no phx-mounted/autofocus focus theft on hydrate to :loaded (populated envelope)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      loaded_html =
        hydrate(view, %{
          "seq" => 1,
          "data" => %{
            "meta" => %{"schema_version" => 1, "seq" => 1},
            "vehicles" => [
              %{
                "vehicle_id" => @car_one,
                "nickname" => "Camry",
                "archived" => false
              }
            ],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      assert_no_focus_theft(loaded_html, :loaded)
    end

    test "no phx-mounted/autofocus focus theft on hydrate to :data_missing (empty payload + has_data boot hint)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # Empty payload + boot_hint="has_data" is the exact combination
      # resolve_state/2 branches to :data_missing on — records were here
      # a mount ago, they are not here now.
      data_missing_html =
        hydrate(view, %{
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      assert_no_focus_theft(data_missing_html, :data_missing)
    end

    test "no phx-mounted/autofocus focus theft on hydrate to :hydration_refused (over-cap payload)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # An over-cap payload trips Caps.check/2 and Session.handle_hydrate
      # takes the {:error, {:cap_exceeded, _}} branch — no records land,
      # local_state becomes :hydration_refused, and the layout still has
      # to render focus-safely.
      refused_html =
        hydrate(view, %{
          "seq" => 1,
          "data" => %{
            "meta" => nil,
            "vehicles" => too_many_vehicles(),
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      assert_no_focus_theft(refused_html, :hydration_refused)
    end

    test "no phx-mounted/autofocus focus theft on hydrate to :storage_unavailable (session_only mode)",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # session_only short-circuits resolve_state/2 to :storage_unavailable
      # regardless of payload content, AND raises the session-only banner
      # in the layout (AC-6). The banner's own DOM must not carry any
      # focus-stealing attribute either — that is what this hydration
      # exercises that the other three do not.
      storage_unavailable_html =
        hydrate(view, %{
          "storage" => %{"mode" => "session_only", "boot_hint" => "never"}
        })

      assert_no_focus_theft(storage_unavailable_html, :storage_unavailable)
    end
  end
end
