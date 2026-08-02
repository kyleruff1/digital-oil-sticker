defmodule DigitalOilStickerWeb.CSPReportController do
  @moduledoc """
  Same-origin sink for CSP violation reports (DOS-M09-007 FR-3).

  This matters most once the policy is ENFORCED. In report-only mode a
  violation is a console message nobody sees; once enforced, the same violation
  is a stylesheet that did not apply or a script that did not run — a broken
  feature, failing silently, for a browser we did not test. The sink is how we
  find out.

  ## Reports are scrubbed to an allowlist, not filtered by denylist

  A CSP report is browser-authored and carries fields that can quote page
  content — `script-sample` is literally a fragment of the blocked script, and
  `referrer` is wherever the user came from. FR-3 requires that a field which
  *could* carry personal data is dropped before storage, so this keeps only
  fields that name **our own policy and our own assets** and discards the rest.
  Anything a future browser adds is dropped by default rather than logged
  because nobody thought about it.

  Even the kept URIs are reduced: scheme, host and path only. This app puts no
  identifier in a URL today, and reducing anyway means that stays true even if
  a future route does.

  ## The sink is the log

  There is no database — the server holds nothing (INV-23), and adding a store
  for violation reports would be the first server-side record of anything. A
  scrubbed report contains no personal data, so it is safe under FR-11, and
  logging is the whole of the storage.
  """
  use DigitalOilStickerWeb, :controller

  require Logger

  # A report is a small JSON object. Anything larger is not a report.
  @max_body_bytes 8_192

  # Fields that describe OUR policy and OUR assets. Everything else — notably
  # `script-sample`, `referrer` and `original-policy` — is dropped.
  @keep ~w(violated-directive effective-directive disposition line-number column-number status-code)

  @uri_fields ~w(document-uri blocked-uri source-file)

  def create(conn, _params) do
    case read_body(conn, length: @max_body_bytes) do
      {:ok, body, conn} ->
        body |> decode() |> log()
        send_resp(conn, :no_content, "")

      # Larger than a report can legitimately be: refuse it unread rather than
      # buffering whatever it is.
      {:more, _partial, conn} ->
        send_resp(conn, 413, "")

      {:error, _reason} ->
        send_resp(conn, :bad_request, "")
    end
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, %{"csp-report" => report}} when is_map(report) -> report
      # Reporting API (report-to) posts an array of reports with a `body`.
      {:ok, [%{"body" => report} | _]} when is_map(report) -> report
      _ -> nil
    end
  end

  defp log(nil), do: :ok

  defp log(report) do
    scrubbed =
      report
      |> Map.take(@keep ++ @uri_fields)
      |> Map.new(fn
        {key, value} when key in @uri_fields -> {key, reduce_uri(value)}
        pair -> pair
      end)

    # Warning, not error: the policy did its job. What needs a human is the
    # question of whether the thing it blocked was ours.
    Logger.warning("csp_violation #{inspect(scrubbed)}")
  end

  # Scheme, host and path. A query string or fragment is dropped whether or not
  # today's routes put anything in one.
  defp reduce_uri(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: nil, path: path} -> path || "(none)"
      %URI{scheme: scheme, host: nil, path: path} -> "#{scheme}:#{path}"
      %URI{scheme: scheme, host: host, path: path} -> "#{scheme}://#{host}#{path}"
    end
  end

  defp reduce_uri(_), do: nil
end
