defmodule DigitalOilStickerWeb.NoDeferredCapabilityControlsTest do
  @moduledoc """
  DOS-M09-003 AC-16: a DOM and copy audit that finds no notification, install,
  offline, or sync control on any user-facing surface — including disabled
  controls — and finds the plain statement that the app does not notify while
  closed. INV-17 says the product must state plainly that it does not notify
  when closed; INV-19 says no deferred capability may be implied by copy or
  by a disabled-but-visible control.

  A disabled control is worse than no control: it renders as a promise that
  the feature exists and will be turned on later. Refusing them here is what
  keeps `DOS-M09-009` (the PWA go/no-go) genuinely deferred rather than
  quietly half-shipped through the UI first.

  Substrings are matched apostrophe-free and case-insensitively so the
  guard survives HEEx entity escaping and minor capitalization edits to
  hypothetical future copy.

  A verify pass on the first version of this suite pointed out that an
  exact-substring allowlist cannot see a natural-language variation: a
  `<button>Get reminders when your oil is due</button>` or a
  `<button disabled>Backup and sync</button>` would advertise a deferred
  capability without hitting any @forbidden_copy entry. The stem-based
  deny list further down matches the SHAPE of those promises — case-
  insensitively, against interactive-control text AND against
  aria-label / title / value attributes — so a rename or a rewording is
  still caught. Same pass also asked us to refuse the install-adjacent
  head signals (manifest, apple-touch-icon, `*-mobile-web-app-capable`)
  on every user-facing route, not just on `/`.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @routes ["/", "/vehicle", "/vehicle/select", "/service/new", "/history", "/settings/storage"]

  # Copy that would advertise a deferred capability. Compared case-
  # insensitively because a future stray "Install App" or "install app" is
  # equally forbidden.
  @forbidden_copy [
    "Install app",
    "Add to home screen",
    "Enable notifications",
    "Offline mode",
    "Sync now",
    "Work offline",
    "Install this app"
  ]

  # Technical strings whose presence would mean a PWA install or service
  # worker path is being wired up regardless of the visible copy.
  @forbidden_technical [
    "beforeinstallprompt",
    "service-worker",
    "sw.js"
  ]

  # Stem-based deny list, case-insensitive. Stems are intentionally broad —
  # they match the shape of a deferred-capability promise instead of one
  # exact phrasing:
  #
  #   * `notif` — "notify", "notification", "notifications"
  #   * `push` — "push", "pushes" (as a capability, not the git verb)
  #   * `reminders?` — "reminder", "reminders" as an active promise
  #     ("Get reminders...") rather than a section heading; we scope the
  #     check to interactive controls, which is why the `<h2>Reminder</h2>`
  #     on the vehicle page does not spuriously fail here
  #   * `install` — "install", "install app", "installable"
  #   * `offline` — "offline", "work offline"
  #   * `\bsync` — "sync now", "in sync"; the word boundary refuses to be
  #     tricked into matching "asynchronous"
  #   * `cache`, `backup` — storage-mode promises
  #   * `add.to.home` — "add to home", "add-to-home", "add_to_home"
  #   * `service.?worker` — "service worker", "serviceworker",
  #     "service-worker" (the last two also caught by @forbidden_technical,
  #     but repeated here so the stem list stands alone as a specification)
  @forbidden_stems ~r/notif|push|reminders?|install|offline|\bsync|cache|backup|add.to.home|service.?worker/i

  # Elements that carry a capability PROMISE by their role. Prose text —
  # paragraphs, headings — is deliberately out of scope: Copy.does_not_notify/0
  # is a categorical DENIAL we want on the page, but its "notify" substring
  # would spuriously match the `notif` stem if we scanned all text. The
  # module is named `NoDeferredCapabilityControls` on purpose — controls are
  # what INV-19 forbids, and controls are what the adversary's failing
  # examples were.
  @stem_control_selectors [
    "button",
    "a",
    "input",
    "textarea",
    "select",
    "[role=button]",
    "[role=link]",
    "[role=menuitem]",
    "[role=switch]",
    "[role=checkbox]",
    "[role=radio]"
  ]

  # Attributes checked on ANY element (not only controls): a button labeled
  # with an icon but `aria-label="Enable notifications"` would slip past a
  # text-only check. `title` and `value` are the other places a control's
  # promise commonly lives outside its visible text.
  @stem_attributes ~w(aria-label title value)

  defp assert_no_forbidden(html, route, phase) do
    lowered = String.downcase(html)

    for phrase <- @forbidden_copy do
      refute lowered =~ String.downcase(phrase),
             "#{route} #{phase} render contains forbidden deferred-capability copy #{inspect(phrase)}"
    end

    for phrase <- @forbidden_technical do
      refute lowered =~ String.downcase(phrase),
             "#{route} #{phase} render contains forbidden deferred-capability marker #{inspect(phrase)}"
    end
  end

  # A disabled-but-visible <button> or <a> with any of the forbidden labels
  # would be the classic INV-19 breach — the feature "exists" and is coming
  # soon. Since we already refute the labels appearing at all, this check is
  # a belt-and-suspenders guard against a future partial fix that only
  # disables the control instead of removing it.
  defp assert_no_disabled_capability_control(html, route, phase) do
    lowered = String.downcase(html)

    for phrase <- @forbidden_copy do
      label = String.downcase(phrase)

      # Match a <button ...>...label...</button> or <a ...>...label...</a>
      # that also carries the `disabled` attribute in the opening tag.
      button_pattern = ~r/<button[^>]*\bdisabled\b[^>]*>[^<]*#{Regex.escape(label)}[^<]*<\/button>/i
      anchor_pattern = ~r/<a[^>]*\bdisabled\b[^>]*>[^<]*#{Regex.escape(label)}[^<]*<\/a>/i

      refute Regex.match?(button_pattern, lowered),
             "#{route} #{phase} render has a disabled <button> labeled #{inspect(phrase)} — INV-19 forbids a disabled-but-visible deferred-capability control."

      refute Regex.match?(anchor_pattern, lowered),
             "#{route} #{phase} render has a disabled <a> labeled #{inspect(phrase)} — INV-19 forbids a disabled-but-visible deferred-capability control."
    end
  end

  for route <- @routes do
    test "#{route} static and post-mount renders contain no deferred-capability controls or copy",
         %{conn: conn} do
      # --- Static (non-connected) render -------------------------------------
      static_html = conn |> get(unquote(route)) |> html_response(200)

      assert_no_forbidden(static_html, unquote(route), "static")
      assert_no_disabled_capability_control(static_html, unquote(route), "static")

      # --- Post-mount (connected LiveView) render ----------------------------
      {:ok, view, mounted_html} = live(conn, unquote(route))

      assert_no_forbidden(mounted_html, unquote(route), "post-mount")
      assert_no_disabled_capability_control(mounted_html, unquote(route), "post-mount")

      # Re-render after mount settles (still pre-hydrate — we deliberately do
      # not fire local_store:hydrate here, so this covers the :hydrating
      # state's DOM). AC-16 covers every state, and the hydrated states are
      # already exercised by the sticker page assertion below and the other
      # state-specific tests in this suite.
      rendered = render(view)
      assert_no_forbidden(rendered, unquote(route), "re-render")
      assert_no_disabled_capability_control(rendered, unquote(route), "re-render")
    end
  end

  describe "the root layout" do
    test "does not link a web app manifest", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      # A manifest link is what makes a browser offer the install prompt.
      # INV-19 and DOS-M09-009 defer PWA installability; the root layout
      # calls this out explicitly in a comment. Guard it in a test so a
      # future edit that adds the link fails here instead of shipping.
      refute html =~ ~r/<link[^>]+rel\s*=\s*["']manifest["']/i,
             "root layout links a web app manifest — PWA installability is deferred (DOS-M09-009 / INV-19)."
    end

    test "does not register a service worker script", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      # A serviceWorker.register(...) call, or a <script src="sw.js">, would
      # activate offline caching — an INV-19 deferred capability. The
      # substring guards already catch "sw.js" and "service-worker"; this
      # is the explicit script-registration pattern.
      refute html =~ ~r/serviceWorker\s*\.\s*register/i,
             "root layout registers a service worker — offline caching is deferred (DOS-M09-009 / INV-19)."

      refute html =~ ~r/navigator\s*\.\s*serviceWorker/i,
             "root layout references navigator.serviceWorker — offline caching is deferred (DOS-M09-009 / INV-19)."
    end
  end

  describe "the sticker page carries the INV-17 statement" do
    # AC-16 requires the plain statement that the app does not notify while
    # closed. Copy.does_not_notify/0 is that string, and it renders in
    # sticker_live's `@view.mode == :sticker` branch — which only appears
    # once hydrate has resolved to :loaded with an active vehicle. So we
    # hydrate a minimal vehicle+event and assert the statement is there.
    defp hydrate(view, data, storage \\ %{"mode" => "idb", "boot_hint" => "never"}) do
      payload = %{
        "envelope" => "dos_local",
        "schema_version" => 1,
        "seq" => Map.get(data, "seq", 0),
        "tab_id" => "test-tab",
        "generated_at" => "2026-08-01T00:00:00Z",
        "data" =>
          Map.merge(
            %{
              "meta" => nil,
              "vehicles" => [],
              "events" => [],
              "readings" => [],
              "usage" => [],
              "reminders" => [],
              "prefs" => nil
            },
            Map.delete(data, "seq")
          ),
        "storage" => storage
      }

      render_hook(view, "local_store:hydrate", payload)
    end

    test "Copy.does_not_notify() renders on / once a vehicle is hydrated", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      vehicle = %{
        "vehicle_id" => "11111111-1111-4111-8111-111111111111",
        "archived" => false,
        "model_year" => 2020,
        "display_snapshot" => %{
          "year" => 2020,
          "make" => "Toyota",
          "model" => "Camry",
          "build" => "LE"
        },
        "maintenance_plan" => %{
          "basis" => "user_entered",
          "interval_months" => 6,
          "interval_miles" => 5000
        }
      }

      event = %{
        "event_id" => "22222222-2222-4222-8222-222222222222",
        "vehicle_id" => "11111111-1111-4111-8111-111111111111",
        "performed_at" => "2026-06-15",
        "odometer_m" => 80_467_200,
        "odometer_input_value" => "50,000",
        "input_unit" => "mi",
        "oil_viscosity" => "5W-30",
        "provenance_mode" => "manual"
      }

      html = hydrate(view, %{"seq" => 3, "vehicles" => [vehicle], "events" => [event]})

      # Substring is apostrophe-free because there is no apostrophe in the
      # copy string — but keep it exact to catch a rename or a rewording.
      assert html =~ Copy.does_not_notify(),
             "sticker page must carry the plain INV-17 statement that the app does not notify while closed."

      # And the hydrated sticker page must still hold no deferred-capability
      # controls or copy.
      assert_no_forbidden(html, "/", "hydrated-sticker")
      assert_no_disabled_capability_control(html, "/", "hydrated-sticker")
    end
  end

  # ---------------------------------------------------------------------------
  # Stem-based deny list — natural-language variations of capability promises
  # ---------------------------------------------------------------------------

  # Walks every interactive control on the page and every element carrying an
  # aria-label/title/value attribute, matches each against @forbidden_stems,
  # and fails with a specific location + phrase on the first hit. Uses the
  # LazyHTML parser (a test-only dep declared in mix.exs) rather than string
  # matching so `LazyHTML.text/1` gives us the actual visible text — a
  # regex over raw HTML would see `class`, `data-*`, and other non-visible
  # attributes and produce noise.
  defp assert_no_forbidden_stems(html, route, phase) do
    doc = LazyHTML.from_document(html)

    for selector <- @stem_control_selectors do
      elems = LazyHTML.filter(doc, selector)

      Enum.each(elems, fn elem ->
        text = elem |> LazyHTML.text() |> String.trim()

        if text != "" do
          case Regex.run(@forbidden_stems, text) do
            [match | _] ->
              flunk(
                "#{route} #{phase} render has an interactive control (selector #{inspect(selector)}) whose text #{inspect(text)} contains forbidden capability stem #{inspect(match)} — INV-19 forbids advertising a deferred capability, even through a natural-language variation like #{inspect(text)}."
              )

            nil ->
              :ok
          end
        end
      end)
    end

    for attr <- @stem_attributes do
      elems = LazyHTML.filter(doc, "[#{attr}]")

      for value <- LazyHTML.attribute(elems, attr), value != "" do
        case Regex.run(@forbidden_stems, value) do
          [match | _] ->
            flunk(
              "#{route} #{phase} render has an element with @#{attr}=#{inspect(value)} containing forbidden capability stem #{inspect(match)} — INV-19 forbids a control advertising a deferred capability through an attribute label either."
            )

          nil ->
            :ok
        end
      end
    end
  end

  describe "the stem-based deny list catches natural-language capability copy" do
    for route <- @routes do
      test "#{route}: interactive-control text and aria/title/value attributes never advertise a deferred capability",
           %{conn: conn} do
        # --- Static (non-connected) render -----------------------------------
        static_html = conn |> get(unquote(route)) |> html_response(200)
        assert_no_forbidden_stems(static_html, unquote(route), "static")

        # --- Post-mount (connected LiveView) render --------------------------
        {:ok, view, mounted_html} = live(conn, unquote(route))
        assert_no_forbidden_stems(mounted_html, unquote(route), "post-mount")

        # --- Re-render after mount settles (still pre-hydrate) ---------------
        rendered = render(view)
        assert_no_forbidden_stems(rendered, unquote(route), "re-render")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Install-adjacent link/meta patterns — checked on every user-facing route
  # ---------------------------------------------------------------------------
  #
  # The root layout already had per-`/` refutes for manifest and service-
  # worker registration. The verify pass asked us to also refute the
  # apple-touch-icon link and the two `*-mobile-web-app-capable` meta
  # declarations — and to apply the whole set on EVERY user-facing route,
  # not just `/`, so a route-specific template that grew its own head slot
  # cannot quietly reintroduce a deferred-capability signal.

  defp assert_no_install_adjacent_head(html, route, phase) do
    # `apple-touch-icon` is deliberately NOT refused: it is only the icon
    # asset iOS uses IF the user themselves chooses "Add to Home Screen"
    # from the browser share menu — a user-initiated bookmark, not an
    # install AFFORDANCE the app offers. The root layout ships one on
    # purpose so the bookmark tile isn't a scaled-up favicon. The
    # deferred capability AC-16 forbids is the app OFFERING install
    # (manifest + install prompt) or claiming standalone-webapp behavior
    # (mobile-web-app-capable metas). Refuting the icon asset itself
    # would over-refute — the root layout even carries a comment
    # explaining the split (root.html.heex, next to the icon link).

    # The two `mobile-web-app-capable` meta names are the classic "when
    # added to the home screen, run standalone (no browser chrome)"
    # declaration. Either one turns the app into an installable-looking
    # webapp; both are refused.
    refute html =~ ~r/<meta[^>]+name\s*=\s*["']apple-mobile-web-app-capable["']/i,
           "#{route} #{phase} render declares apple-mobile-web-app-capable — standalone-webapp declarations are deferred (DOS-M09-009 / INV-19)."

    refute html =~ ~r/<meta[^>]+name\s*=\s*["']mobile-web-app-capable["']/i,
           "#{route} #{phase} render declares mobile-web-app-capable — standalone-webapp declarations are deferred (DOS-M09-009 / INV-19)."

    # rel="manifest" is the browser trigger for the install prompt. The
    # root-layout describe block above already refutes it for `/`; this
    # repeats the refute per-route so a route-specific template that grew
    # its own head slot cannot slip a manifest link past this suite.
    refute html =~ ~r/<link[^>]+rel\s*=\s*["']manifest["']/i,
           "#{route} #{phase} render links a web app manifest — PWA installability is deferred (DOS-M09-009 / INV-19)."
  end

  describe "install-adjacent link/meta patterns are absent on every user-facing route" do
    for route <- @routes do
      test "#{route}: head has no manifest, apple-touch-icon, or standalone-webapp declarations",
           %{conn: conn} do
        # --- Static render — this is what a pre-hydrate crawler sees ---------
        static_html = conn |> get(unquote(route)) |> html_response(200)
        assert_no_install_adjacent_head(static_html, unquote(route), "static")

        # --- Post-mount and re-render — belt-and-suspenders in case a future
        #     `<Layouts.app>` slot or a per-route dynamic head grew a stray
        #     install-adjacent link after mount. Both trivially pass when the
        #     rendered fragment carries no <head> at all.
        {:ok, view, mounted_html} = live(conn, unquote(route))
        assert_no_install_adjacent_head(mounted_html, unquote(route), "post-mount")

        rendered = render(view)
        assert_no_install_adjacent_head(rendered, unquote(route), "re-render")
      end
    end
  end
end
