defmodule DigitalOilSticker.NoOsNotificationsTest do
  @moduledoc """
  AC-4 / INV-17 / ADR-0004 §"Lost — honestly": the browser MVP has no
  OS-notification code path. Reminder intent is presented as in-app due state
  only. There is no server-side scheduler, no `mob_notify` call site, no Web
  Push subscription — because none of these exist in the current architecture,
  a source-scan for their names must find nothing.

  The value of the scan is negative: it makes accidental reintroduction of an
  OS-notification path (from a copy-paste, a stale example, or a pre-pivot
  branch) fail the build the moment it lands, rather than at manual audit.
  """
  use ExUnit.Case, async: true

  @app_root Path.expand("../..", __DIR__)

  # API-surface patterns only. The point is to fail on actual call sites, not
  # on docstrings that explain why these paths do not exist. If a comment or
  # `@moduledoc` mentions "Web Push" as prose, that is documentation of the
  # boundary, not a violation of it.
  @forbidden_patterns [
    ~r/\bmob_notify\b/i,
    ~r/\bMobNotify\./,
    ~r/\bLocalNotifications?\.schedule\b/,
    ~r/\bpushManager\.(subscribe|getSubscription)\b/,
    ~r/\bshowNotification\s*\(/,
    ~r/\bnew Notification\s*\(/,
    ~r/\bNotifications?\.requestPermission\s*\(/
  ]

  @source_roots ~w(lib assets/js)

  defp source_files do
    for root <- @source_roots,
        pattern <- ["**/*.ex", "**/*.exs", "**/*.js", "**/*.ts"],
        path <- Path.wildcard(Path.join([@app_root, root, pattern])),
        # Do not scan this test file — the forbidden patterns appear here by
        # design.
        Path.basename(path) != "no_os_notifications_test.exs" do
      {Path.relative_to(path, @app_root), path |> File.read!() |> String.replace("\r\n", "\n")}
    end
  end

  defp strip_comments(source, ext) do
    comment_prefix =
      case ext do
        ".ex" -> "#"
        ".exs" -> "#"
        _ -> "//"
      end

    source
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?(comment_prefix)))
    |> Enum.join("\n")
  end

  test "no source file references any OS-notification API" do
    sources = source_files()
    assert length(sources) > 10, "no source files scanned — glob is broken"

    offenders =
      for {path, source} <- sources,
          code = strip_comments(source, Path.extname(path)),
          pattern <- @forbidden_patterns,
          code =~ pattern do
        {path, inspect(pattern)}
      end

    assert offenders == [],
           "OS-notification code path found:\n" <>
             Enum.map_join(offenders, "\n", fn {p, pat} -> "  #{p} matched #{pat}" end)
  end

  test "positive control: the scanner detects a synthetic violation" do
    synthetic = """
    // service worker registration
    ServiceWorkerRegistration.showNotification("stale reminder");
    new Notification("stale reminder");
    """

    matches =
      Enum.filter(@forbidden_patterns, fn pattern ->
        strip_comments(synthetic, ".js") =~ pattern
      end)

    # At least the two obvious ones must trip. If neither does, the scanner is
    # not doing what the assertion above trusts it to do.
    assert length(matches) >= 2
  end
end
