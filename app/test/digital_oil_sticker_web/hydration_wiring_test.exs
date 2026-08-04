defmodule DigitalOilStickerWeb.HydrationWiringTest do
  @moduledoc """
  Regression guard for the wiring bug that shipped to production: the
  LocalStore hook element lives in Layouts.app, so a LiveView that does not
  wrap its render in `<Layouts.app>` never mounts the hook, hydration never
  runs, and the 5s deadline reports storage_unavailable on a browser whose
  storage is perfectly fine.

  AC-5 additions (DOS-M09-002): neither the static (non-connected) render
  nor the :hydrating render (LiveView mounted, hydrate event not yet fired)
  may show empty-garage or onboarding-from-zero prose. Those Copy strings —
  Copy.empty_heading/0 and the distinctive body phrases from
  Copy.empty_body/0 and Copy.data_missing_body/0 — are only correct AFTER
  hydrate resolves the garage to :empty or :data_missing. Rendering them
  before hydrate has been asked is the "empty garage on cold-open" bug the
  wiring test guards against: a user with data in their browser would see
  "Set up your first vehicle" for a flash before the hook mounts and
  hydration lands, or worse, permanently if hydration never runs because
  the hook element is missing (the AC-1..AC-4 guarantee).

  Refutes are scoped to HEADINGS, not to body prose. The headings ("Set up
  your first vehicle", the data-missing heading) are load-bearing on the
  storage state — rendering one is a claim about what the browser holds.
  The body prose (empty_body, data_missing_body) explains the storage
  model in general terms and appears legitimately on the /settings/storage
  diagnostics page regardless of state; refuting it there was a false
  positive. HEEx escapes apostrophes to `&#39;`, so the data-missing
  heading substring is chosen apostrophe-free (see error_mapping_test.exs
  for the same pattern).
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @routes ["/", "/vehicle", "/vehicle/select", "/service/new", "/history", "/settings/storage"]

  # Narrow substrings from Copy headings that would only render once
  # hydrate has resolved to :empty or :data_missing. Bodies are excluded
  # because they explain the storage model and can appear on informational
  # surfaces without being state claims.
  @empty_heading Copy.empty_heading()
  @data_missing_heading_phrase "stored records are gone"

  for route <- @routes do
    test "#{route} renders LocalStore hook and hides empty/onboarding headings in static and :hydrating renders",
         %{conn: conn} do
      # --- Static (non-connected) render -------------------------------------
      html = conn |> get(unquote(route)) |> html_response(200)

      assert html =~ ~s(id="local-store"),
             "#{unquote(route)} is missing the LocalStore hook element — is its render wrapped in <Layouts.app>?"

      assert html =~ ~s(phx-hook="LocalStore")

      # The static render happens before any browser has been asked about
      # its storage — showing an empty-garage or data-missing heading here
      # would be a lie about what we know.
      refute html =~ @empty_heading,
             "#{unquote(route)} static render shows Copy.empty_heading() before hydration — the empty-garage view was rendered before we asked the browser."

      refute html =~ @data_missing_heading_phrase,
             "#{unquote(route)} static render shows Copy.data_missing_heading() prose before hydration."

      # --- :hydrating render (LiveView mounted, hydrate not yet fired) -------
      {:ok, view, hydrating_html} = live(conn, unquote(route))

      # Same invariant on the initial LiveView render: local_state == :hydrating
      # here, and the empty/data-missing headings are only correct after hydrate.
      refute hydrating_html =~ @empty_heading,
             "#{unquote(route)} :hydrating render shows Copy.empty_heading() before hydrate fires."

      refute hydrating_html =~ @data_missing_heading_phrase,
             "#{unquote(route)} :hydrating render shows Copy.data_missing_heading() prose before hydrate fires."

      # And re-rendering the same still-:hydrating view — no hydrate has
      # been fired between these calls — must remain clean.
      rendered = render(view)

      refute rendered =~ @empty_heading
      refute rendered =~ @data_missing_heading_phrase
    end
  end
end
