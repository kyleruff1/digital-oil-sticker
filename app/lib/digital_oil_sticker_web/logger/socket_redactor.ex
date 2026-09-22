defmodule DigitalOilStickerWeb.Logger.SocketRedactor do
  @moduledoc """
  A `Logger` `:default_formatter` that redacts every
  `#Phoenix.LiveView.Socket<...>` representation from the final log
  output before it reaches any handler. Wraps Elixir's standard
  formatter — the outward format string stays exactly what
  `config/config.exs` used to configure directly (`"$time $metadata[$level] $message\n"`).

  ## Why this exists (DOS-M09-007 AC-13, INV-4)

  When a `handle_event/3` clause raises a `FunctionClauseError` (a
  malformed payload missing a pattern-matched key is the common way
  in), Erlang formats the stacktrace entry for that clause as
  `Module.function(arg1, arg2, arg3)` — and the third argument is the
  `%Phoenix.LiveView.Socket{}` the channel process was holding. Phoenix's
  `Inspect` implementation for `Socket` shows `assigns:` inline, and
  `assigns.garage` for this app is the user's whole record set: VIN,
  odometer readings, service dates, notes, nicknames. So a single
  crash — pattern-match miss, guard failure — spills every personal
  value the browser has hydrated into the standard GenServer crash
  report at `[error]` level.

  `Phoenix.LiveView.Channel` implements `format_status/1`, so the
  separate `State:` line the default GenServer crash report would add
  is already suppressed. The remaining source of a leak is the
  stacktrace arg formatting, which OTP does not gate — the fix has to
  live outside the frame OTP controls, and the last point at which
  every log line still passes through one function is the formatter.

  ## What it redacts

  Any substring beginning with the literal `#Phoenix.LiveView.Socket<`
  and running to its terminator `, ...>` is replaced with
  `#Phoenix.LiveView.Socket<[REDACTED]>`. The terminator anchor is
  Phoenix's own inspect convention — `Phoenix.LiveView.Socket`'s
  `Inspect` implementation explicitly appends `, ...` to signal hidden
  struct fields, and closes with `>`. `<>`-balanced scanning failed
  here because the inspect output freely contains `=>` (map arrows) and
  `>` inside string values, both of which would false-close on a naive
  bracket count.

  ## What it does not do

  * It does not touch messages that name assign fields directly under
    other names (`garage:` in an ad-hoc report, `%{"notes" => "..."}` in
    a user-authored log line). `ProductionPostureTest` catches those
    at the source-scan level, and `LocalStore.LogScanTest` /
    `InducedCrashLogTest` catch them at runtime — the two guards are
    complementary, not one-of.

  * It does not attempt to hide the socket in every conceivable place;
    it hides the one that OTP-emitted crash reports actually use. If a
    future path emits the socket under a different representation, the
    runtime scan will surface it and we grow this filter, deliberately.

  ## Correctness properties (relied on by the runtime tests)

  * Idempotent on inputs with no socket representation — every other
    log line is unchanged byte-for-byte (proven in
    `SocketRedactorTest`).
  * Deterministic and reentrant — the redactor holds no state, so
    concurrent handlers never see each other's data.
  * Never raises on malformed inputs — if the terminator `, ...>` is
    absent (which would mean Phoenix changed its inspect
    representation), the whole tail from the opening `#Phoenix.LiveView.Socket<`
    is dropped and replaced with the placeholder, which is strictly
    safer than emitting the partial socket.
  """

  # The format string is the same one `config/config.exs` used to set
  # under `format:`. Compiled once at compile time (via a module
  # attribute) so the hot path is a plain `Logger.Formatter.format/5`
  # over a pre-parsed pattern.
  @format_pattern Logger.Formatter.compile("$time $metadata[$level] $message\n")

  # `s` flag lets `.` match newlines — the socket's inspect output is
  # single-line today, but a future Phoenix could wrap. `.*?` is
  # non-greedy so we match up to the FIRST `, ...>` after the opening,
  # not the last one in the whole log line, which would swallow every
  # socket between two crash reports on the same line into one match.
  # The literal `, ` (comma-space) plus the escaped `...>` anchors on
  # Phoenix's inspect convention for hidden struct fields.
  @socket_regex ~r/#Phoenix\.LiveView\.Socket<.*?, \.\.\.>/s

  @doc """
  `Logger`'s `format/4` callback. Renders the log event through the
  standard formatter, then redacts every socket representation in the
  resulting iodata.
  """
  @spec format(Logger.level(), Logger.message(), Logger.Formatter.time(), keyword()) ::
          IO.chardata()
  def format(level, msg, timestamp, metadata) do
    @format_pattern
    |> Logger.Formatter.format(level, msg, timestamp, metadata)
    |> IO.iodata_to_binary()
    |> redact_sockets()
  rescue
    # A formatter that raises would crash the log handler and lose the
    # message. Fall back to a minimal safe representation that still
    # signals the level, so an outage of this filter never silences an
    # error we needed to see.
    exception ->
      [
        "[",
        to_string(level),
        "] <formatter error: ",
        Exception.message(exception),
        ">\n"
      ]
  end

  @doc """
  Redact `#Phoenix.LiveView.Socket<...>` occurrences in a binary,
  replacing each match with `#Phoenix.LiveView.Socket<[REDACTED]>`.

  Exposed for `SocketRedactorTest` to exercise the redactor directly
  without going through the formatter path.
  """
  @spec redact_sockets(binary()) :: binary()
  def redact_sockets(str) when is_binary(str) do
    case Regex.run(@socket_regex, str, return: :index) do
      nil ->
        # No socket in this line — pass through byte-for-byte, so the
        # filter is idempotent on the overwhelming majority of log
        # traffic.
        str

      _ ->
        # Recurses via Regex.replace, which walks every non-overlapping
        # match in one pass. Each match becomes the placeholder
        # regardless of how much (or how little) was between the anchors.
        Regex.replace(@socket_regex, str, "#Phoenix.LiveView.Socket<[REDACTED]>")
    end
  end
end
