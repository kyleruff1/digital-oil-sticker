defmodule DigitalOilStickerWeb.CSPReportTest do
  @moduledoc """
  The CSP violation sink, and what it refuses to keep (DOS-M09-007 FR-3, FR-11).

  A CSP report is written by the browser, not by us, and two of its fields
  routinely quote the page: `script-sample` is a literal fragment of the blocked
  script, and `referrer` is wherever the user came from. FR-3 requires that a
  field which could carry personal data is dropped before storage, so this
  asserts the allowlist actually holds against a report built to carry the
  worst case.
  """
  use DigitalOilStickerWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  @vin "1HGCM82633A004352"
  @odometer "87431"

  defp hostile_report do
    %{
      "csp-report" => %{
        # A path is fine; the query string is where something could ride along.
        "document-uri" =>
          "https://digital-oil-sticker.fly.dev/history?odometer=#{@odometer}&note=private",
        "referrer" => "https://somewhere-private.example/whatever",
        "violated-directive" => "style-src",
        "effective-directive" => "style-src-attr",
        "blocked-uri" => "inline",
        "source-file" => "https://digital-oil-sticker.fly.dev/assets/app.js?vsn=d",
        "line-number" => 42,
        "column-number" => 7,
        "status-code" => 200,
        "disposition" => "enforce",
        # The browser quoting page content straight back at us.
        "script-sample" => "const vin = '#{@vin}'",
        "original-policy" => "default-src 'self'; script-src 'self'"
      }
    }
  end

  defp post_report(conn, body) do
    conn
    |> put_req_header("content-type", "application/csp-report")
    |> post(~p"/csp-report", Jason.encode!(body))
  end

  test "accepts a report and answers 204", %{conn: conn} do
    conn = post_report(conn, hostile_report())

    assert conn.status == 204
  end

  test "keeps what makes a violation actionable", %{conn: conn} do
    log = capture_log(fn -> post_report(conn, hostile_report()) end)

    # Without these the report says a violation happened and nothing else.
    assert log =~ "csp_violation"
    assert log =~ "style-src"
    assert log =~ "/history"
    assert log =~ "42"
  end

  test "drops the script sample, which is page content by definition", %{conn: conn} do
    log = capture_log(fn -> post_report(conn, hostile_report()) end)

    refute log =~ @vin,
           "the log carries script-sample, which quotes whatever the blocked script contained"
  end

  test "drops the referrer", %{conn: conn} do
    log = capture_log(fn -> post_report(conn, hostile_report()) end)

    refute log =~ "somewhere-private"
  end

  test "reduces URIs so a query string cannot ride along", %{conn: conn} do
    log = capture_log(fn -> post_report(conn, hostile_report()) end)

    # No route puts an identifier in a query string today. Reducing anyway is
    # what keeps that true if one ever does.
    refute log =~ @odometer
    refute log =~ "note=private"
    refute log =~ "vsn=d"
  end

  test "drops a field it has never heard of, rather than logging it", %{conn: conn} do
    report = put_in(hostile_report(), ["csp-report", "future-field"], "1HGCM82633A004352-again")

    log = capture_log(fn -> post_report(conn, report) end)

    # An allowlist, not a denylist: a field a future browser adds is dropped by
    # default instead of logged because nobody thought about it yet.
    refute log =~ "future-field"
    refute log =~ "again"
  end

  test "accepts the Reporting API shape as well as the legacy one", %{conn: conn} do
    body = [
      %{"body" => %{"violated-directive" => "img-src", "blocked-uri" => "https://evil.example/x"}}
    ]

    log = capture_log(fn -> post_report(conn, body) end)

    assert log =~ "img-src"
  end

  test "a body that is not a report is refused without crashing", %{conn: conn} do
    conn = post_report(conn, %{"not" => "a report"})

    assert conn.status == 204
  end

  test "an oversized body is refused unread", %{conn: conn} do
    huge = %{"csp-report" => %{"script-sample" => String.duplicate("x", 20_000)}}

    conn = post_report(conn, huge)

    # Buffering whatever someone posts to an unauthenticated endpoint is the
    # thing to avoid; a real report is a small object.
    assert conn.status == 413
  end
end
