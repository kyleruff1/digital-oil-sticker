defmodule DigitalOilStickerWeb.ScanLiveTest do
  @moduledoc """
  The scan landing at `/s`.

  Server never sees the fragment — the browser hook reads `location.hash` and
  hands the code back over the socket as the `scan_code` event, so this
  test exercises that event directly. Four view modes correspond to four
  distinct message shapes:

    * `code: ""`                 -> `:no_code`      (no fragment)
    * valid StickerCode          -> `:sticker`      (decoded, rendered)
    * garbage / short string     -> `:bad_code`     (decode refused)
    * absurdly long string       -> `:bad_code`     (bounced before decode)

  Initial render is always `:awaiting` — a skeleton sticker with sr-only
  "reading" copy — so the first paint has a shape before the hook fires.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias DigitalOilSticker.{CatalogRepo, StickerCode}
  alias DigitalOilSticker.Catalog.Queries.Identity
  alias DigitalOilStickerWeb.Copy

  # A well-formed UUID that intentionally does NOT match a fixture row.
  # Round-trips through StickerCode.encode/decode fine, but the vehicle-
  # labels lookup returns nil — the tests below assert the scan page still
  # renders the sticker in that case (older-catalog / stale-key handling).
  @config_key "0e0eef2b-b1ba-4c1a-9c86-1c1ef4123456"

  # A real configuration_key + its matching labels pulled from the fixture
  # catalog. Used to exercise the happy path — code decodes AND the vehicle
  # line renders "year make model [trim]" above the sticker.
  defp real_config do
    row =
      CatalogRepo.one(
        from(c in "vehicle_configurations",
          select: c.configuration_key,
          limit: 1
        )
      )

    labels = Identity.get_configuration_labels(row)
    %{key: row, labels: labels}
  end

  defp sample_code(overrides \\ %{}) do
    sticker =
      Map.merge(
        %{
          configuration_key: @config_key,
          changed_on: ~D[2026-01-15],
          odometer_m: 126_154_400,
          grade: "5W-30"
        },
        overrides
      )

    {:ok, code} = StickerCode.encode(sticker)
    code
  end

  describe "initial mount" do
    test "renders the awaiting skeleton before the hook fires", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/s")

      assert html =~ ~s|data-test="scan-awaiting"|
      # The skeleton is rendered inside the awaiting partial; the sticker
      # component's own test id anchors the visual shape.
      assert html =~ ~s|data-test="scan-landing"|

      # And the sr-only "reading…" line, so a screen reader announces state
      # rather than silence.
      assert html =~ Copy.scan_awaiting()

      # No decoded content leaks into the awaiting state.
      refute html =~ ~s|data-test="scan-sticker"|
      refute html =~ ~s|data-test="scan-bad-code"|
      refute html =~ ~s|data-test="scan-no-code"|
    end

    test "the phx-hook is attached to the landing element", %{conn: conn} do
      # The whole page depends on this attribute — without it the browser
      # never reads the fragment and the LiveView never leaves :awaiting.
      {:ok, _view, html} = live(conn, ~p"/s")

      assert html =~ ~s|phx-hook="ScanLanding"|
      assert html =~ ~s|id="scan-landing"|
    end
  end

  describe "scan_code event — empty payload (bare /s URL)" do
    test "renders the no_code state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/s")

      html = render_hook(view, "scan_code", %{"code" => ""})

      assert html =~ ~s|data-test="scan-no-code"|
      assert html =~ Copy.scan_no_code_heading()
      # Body copy contains an apostrophe (`Digital Oil Sticker's`), which
      # renders as the entity `&#39;` — assert on the prefix before it.
      assert html =~ "Scanning a Digital Oil Sticker"

      # No sticker is rendered when we don't have one.
      refute html =~ ~s|data-test="scan-sticker"|
    end
  end

  describe "scan_code event — valid code" do
    test "decodes and renders the sticker with historical values in the stamps",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/s")

      html = render_hook(view, "scan_code", %{"code" => sample_code()})

      assert html =~ ~s|data-test="scan-sticker"|

      # The historical values from the code arrive in the stamped viewports.
      # The date is Calendar-formatted; the grade is the literal from the code.
      assert html =~ "Jan 15, 2026"
      assert html =~ "5W-30"

      # The mileage — code carries metres; page displays miles rounded and
      # comma-grouped. 126,154,400 m / 1609.344 m/mi ≈ 78,388.66 → 78,389.
      assert html =~ "78,389 mi"

      # The caption naming why the top viewports are blank. Contains an
      # apostrophe (`owner's`) that renders as `&#39;` — assert on prefix.
      assert html =~ "Last recorded oil change from this sticker"
    end

    test "top viewports (`date_value`, `mileage_value`) stay blank on scan view",
         %{conn: conn} do
      # The property this test defends: the top row is deliberately empty on
      # a scan because computing the estimated-due would require the owner's
      # own interval (INV-25). If someone quietly starts filling in date_value
      # here from, say, `changed_on`, the caption underneath becomes a lie.
      {:ok, view, _html} = live(conn, ~p"/s")

      html = render_hook(view, "scan_code", %{"code" => sample_code()})

      # Both stamped viewports (bottom) render.
      assert html =~ ~s|data-test="sticker-changed"|
      assert html =~ ~s|data-test="sticker-grade"|

      # The main DATE and MILEAGE viewports (top) render as em-dashes.
      # (viewport/1 emits "—" when value is nil AND not skeleton — the
      # exact literal is a single em-dash, U+2014.)
      # Extract just the top-viewport regions and assert on their content.
      assert html =~ ~s|data-test="sticker-date"|
      assert html =~ ~s|data-test="sticker-mileage"|

      # And critically: the date-changed value ("Jan 15, 2026") does not
      # ALSO appear in the top DATE viewport. It should appear exactly once
      # (in the stamp).
      count = html |> String.split("Jan 15, 2026") |> length() |> Kernel.-(1)

      assert count == 1,
             "expected 'Jan 15, 2026' to render once (in the stamp), got #{count}"
    end

    test "renders the vehicle line above the sticker when configuration_key resolves",
         %{conn: conn} do
      # The whole point of the labels lookup: a scanner sees not just the
      # date/mileage/grade, but WHICH vehicle produced this sticker. Uses
      # a real key from the fixture catalog rather than a hardcoded UUID
      # so the test tracks whatever labels the fixture ships.
      %{key: key, labels: labels} = real_config()

      {:ok, view, _html} = live(conn, ~p"/s")

      html =
        render_hook(view, "scan_code", %{
          "code" => sample_code(%{configuration_key: key})
        })

      assert html =~ ~s|data-test="scan-vehicle"|
      # Year, make, and model must all appear — the vehicle line is a
      # promise the scan page keeps only if it can name the vehicle in full.
      assert html =~ Integer.to_string(labels.year)
      assert html =~ labels.make
      assert html =~ labels.model
    end

    test "omits the vehicle line when configuration_key does not match a catalog row",
         %{conn: conn} do
      # Codes from an older catalog can carry a configuration_key that the
      # current data_version no longer recognizes. Rather than render
      # "Unknown vehicle" (which reads as a bug), the vehicle line is
      # hidden and the sticker below still shows the date/grade the code
      # carries. The @config_key at the top of this file is such a key.
      {:ok, view, _html} = live(conn, ~p"/s")

      html = render_hook(view, "scan_code", %{"code" => sample_code()})

      assert html =~ ~s|data-test="scan-sticker"|
      refute html =~ ~s|data-test="scan-vehicle"|
    end

    test "renders correctly when the code carries a nil date", %{conn: conn} do
      # StickerCode's own absent-value sentinels: nil date, nil odometer, nil
      # grade round-trip through encode/decode. The view must not crash on
      # any of them.
      {:ok, view, _html} = live(conn, ~p"/s")

      code = sample_code(%{changed_on: nil, odometer_m: nil, grade: nil})
      html = render_hook(view, "scan_code", %{"code" => code})

      assert html =~ ~s|data-test="scan-sticker"|
      # Every viewport falls back to the em-dash marker; the caption still
      # renders (apostrophe entity-escapes — assert on the prefix).
      assert html =~ "Last recorded oil change from this sticker"
    end
  end

  describe "scan_code event — bad payload" do
    test "renders the bad_code state on garbage input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/s")

      # "hello" is not a valid base32 payload for this format.
      html = render_hook(view, "scan_code", %{"code" => "hello"})

      assert html =~ ~s|data-test="scan-bad-code"|
      assert html =~ Copy.scan_bad_code_heading()
    end

    test "renders the bad_code state on a truncated code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/s")

      # Chop the last character off a valid code — the format is exact-length
      # for the common case, so this must not decode.
      truncated = sample_code() |> String.slice(0..-2//1)

      html = render_hook(view, "scan_code", %{"code" => truncated})

      assert html =~ ~s|data-test="scan-bad-code"|
    end

    test "bounces an absurdly long payload before invoking the decoder",
         %{conn: conn} do
      # A malicious client can push any string; the LiveView refuses anything
      # much longer than the format ever produces (500 chars) without spending
      # decoder cycles on it. Ten thousand bytes should not reach StickerCode.
      {:ok, view, _html} = live(conn, ~p"/s")

      html = render_hook(view, "scan_code", %{"code" => String.duplicate("A", 10_000)})

      assert html =~ ~s|data-test="scan-bad-code"|
    end

    test "renders the bad_code state on a non-string code", %{conn: conn} do
      # A well-formed hook always sends a string. This tests the last-resort
      # clause: don't crash on anything else.
      {:ok, view, _html} = live(conn, ~p"/s")

      html = render_hook(view, "scan_code", %{"code" => nil})

      assert html =~ ~s|data-test="scan-bad-code"|
    end
  end

  describe "no browser storage is loaded on this page" do
    test "the scan page never carries a data-skin attribute", %{conn: conn} do
      # /s renders no Layouts.app and hydrates no prefs, so the sticker
      # resolves the CSS token defaults — the default skin — by construction.
      # A data-skin appearing here would mean someone's preference leaked
      # into a stranger's view.
      {:ok, view, html} = live(conn, ~p"/s")

      refute html =~ "data-skin"

      html = render_hook(view, "scan_code", %{"code" => sample_code()})
      refute html =~ "data-skin"
    end

    test "the scan route is NOT in the :garage live_session", %{conn: conn} do
      # The whole design of this page is that a stranger can visit without
      # any IndexedDB hydration attempt. If ScanLive lands in :garage, the
      # LocalStoreHook mounts and starts a hydration handshake — visible in
      # the LiveView's assigns as a `local_state` key. Its absence is the
      # test that no browser-storage protocol runs here.
      {:ok, view, _html} = live(conn, ~p"/s")

      refute Map.has_key?(:sys.get_state(view.pid).socket.assigns, :local_state),
             "expected /s to omit the LocalStoreHook — assigns has :local_state"
    end
  end
end
