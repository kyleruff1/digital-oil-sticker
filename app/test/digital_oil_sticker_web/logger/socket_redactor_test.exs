defmodule DigitalOilStickerWeb.Logger.SocketRedactorTest do
  @moduledoc """
  Unit tests for the socket-redactor's scanner and formatter callback.

  `InducedCrashLogTest` is the end-to-end guard — it proves that under
  a real LiveView crash no PII from `socket.assigns` reaches the log.
  These tests exercise `redact_sockets/1` and `format/4` on isolated
  inputs so a regression in the redactor is diagnosable from the
  redactor's own test file rather than an unrelated LiveView crash test.
  """
  use ExUnit.Case, async: true

  alias DigitalOilStickerWeb.Logger.SocketRedactor

  describe "redact_sockets/1" do
    test "returns non-socket input unchanged (idempotent for the common case)" do
      # Overwhelmingly most log traffic carries no socket at all;
      # every unchanged pass-through is a byte-for-byte comparison so
      # a whitespace/encoding drift by the filter is a failure here.
      assert SocketRedactor.redact_sockets("plain text") == "plain text"
      assert SocketRedactor.redact_sockets("") == ""

      assert SocketRedactor.redact_sockets("2026-08-01 [info] request completed in 3ms") ==
               "2026-08-01 [info] request completed in 3ms"
    end

    test "replaces a single socket inspect with the redacted placeholder" do
      input =
        "handle_event(\"foo\", %{}, #Phoenix.LiveView.Socket<id: \"phx-xyz\", assigns: %{garage: %{}}, sticky?: nil, ...>)"

      assert SocketRedactor.redact_sockets(input) ==
               "handle_event(\"foo\", %{}, #Phoenix.LiveView.Socket<[REDACTED]>)"
    end

    test "handles socket inspects whose assigns contain map arrows and nested inspects" do
      # `=>` (map arrow) and `#PID<0.360.0>` are the two structural
      # tokens that a naive `<>`-balanced scanner would false-close
      # or false-open on. Both appear here and the redaction has to
      # still consume the socket up to `, ...>`.
      input =
        "prefix #Phoenix.LiveView.Socket<id: \"phx-abc\", root_pid: #PID<0.360.0>, " <>
          "assigns: %{garage: %{events: [%{\"vin_last6\" => \"SECRET1\", " <>
          "\"notes\" => \"SECRET2\"}]}}, transport_pid: #PID<0.358.0>, sticky?: nil, ...>" <>
          " suffix"

      output = SocketRedactor.redact_sockets(input)

      # The redaction covers the whole socket.
      assert output == "prefix #Phoenix.LiveView.Socket<[REDACTED]> suffix"
      refute output =~ "SECRET1"
      refute output =~ "SECRET2"
    end

    test "redacts multiple sockets on one line without merging them" do
      # A crash report can carry more than one socket (e.g. nested
      # channels, or two crash lines that share a log record). Each
      # must redact independently — non-greedy `.*?` matching is what
      # guarantees that; a greedy match would swallow everything
      # between the first `<` and the last `, ...>`, taking with it
      # any log text between the two sockets.
      input =
        "a #Phoenix.LiveView.Socket<id: 1, assigns: %{}, sticky?: nil, ...> b " <>
          "#Phoenix.LiveView.Socket<id: 2, assigns: %{}, sticky?: nil, ...> c"

      assert SocketRedactor.redact_sockets(input) ==
               "a #Phoenix.LiveView.Socket<[REDACTED]> b #Phoenix.LiveView.Socket<[REDACTED]> c"
    end

    test "does not touch a socket-like string that lacks the terminator anchor" do
      # If Phoenix's inspect impl ever changes and drops the `, ...>`
      # terminator, this filter stops matching — which is a visible
      # regression a runtime scan (LocalStore.LogScanTest,
      # InducedCrashLogTest) catches immediately. It does NOT silently
      # match a partial string here, which would be a false-positive
      # (something starting with `#Phoenix.LiveView.Socket<` that is
      # not actually a socket).
      #
      # The safety of that failure mode is asymmetric: a silent
      # non-match leaks socket contents in one log line and gets caught
      # by the runtime tests; a silent partial-match would corrupt
      # every log line's tail. This test locks in the non-match
      # behavior so nobody "fixes" it by loosening the pattern.
      input = "#Phoenix.LiveView.Socket<id: 1, assigns: %{}"

      assert SocketRedactor.redact_sockets(input) == input
    end

    test "is idempotent when applied twice" do
      input =
        "#Phoenix.LiveView.Socket<id: \"phx-x\", assigns: %{}, sticky?: nil, ...>"

      once = SocketRedactor.redact_sockets(input)
      twice = SocketRedactor.redact_sockets(once)

      # The placeholder itself does not contain `, ...>`, so a second
      # pass over it must NOT match anything — running the redactor
      # twice on the same input produces the same output as once. If
      # the placeholder were changed to end in `, ...>`, the second
      # pass would re-match and this test would fail.
      assert once == twice
      assert once == "#Phoenix.LiveView.Socket<[REDACTED]>"
    end
  end

  describe "format/4 callback" do
    test "emits the standard '$time $metadata[$level] $message' format for a benign message" do
      ts = {{2026, 8, 1}, {3, 14, 15, 0}}
      output = SocketRedactor.format(:info, "hello", ts, [])
      binary = IO.iodata_to_binary(output)

      # Preserves the outward format string config/config.exs used to
      # set directly: "$time $metadata[$level] $message\n".
      assert binary =~ "[info]"
      assert binary =~ "hello"
      assert String.ends_with?(binary, "\n")
    end

    test "redacts a socket embedded in the message before returning iodata" do
      ts = {{2026, 8, 1}, {3, 14, 15, 0}}

      msg =
        "crash: handle_event(\"foo\", %{}, " <>
          "#Phoenix.LiveView.Socket<id: \"phx-x\", assigns: %{vin: \"LEAKY\"}, sticky?: nil, ...>)"

      output = SocketRedactor.format(:error, msg, ts, [])
      binary = IO.iodata_to_binary(output)

      refute binary =~ "LEAKY",
             "formatter emitted the socket inspect contents into its output — the redactor " <>
               "either did not run or did not match the sentinel"

      assert binary =~ "#Phoenix.LiveView.Socket<[REDACTED]>"
    end

    test "falls back to a level-tagged marker if the formatter itself raises" do
      # An unstructured, non-string, non-report message that
      # Logger.Formatter.format/5 cannot render. The rescue clause
      # inside format/4 must catch it and emit SOMETHING at the same
      # level, or the log handler would crash and lose every message
      # from that point on. Correctness here is "did not raise and
      # includes the level"; the exact text of the fallback is a
      # documentation detail, not a contract.
      ts = {{2026, 8, 1}, {3, 14, 15, 0}}

      output = SocketRedactor.format(:error, {:not_a_valid_msg_form, :nope}, ts, [])
      binary = IO.iodata_to_binary(output)

      assert binary =~ "[error]"
    end
  end
end
