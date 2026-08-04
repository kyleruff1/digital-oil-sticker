defmodule DigitalOilSticker.Catalog.LogScanTest do
  @moduledoc """
  DOS-M09-004 AC-13 — the catalog query path is the runtime companion to the
  static/structural checks in `ImpersonalSelectorTest` and
  `QueryInspectionTest`. Those enumerate the closed vocabulary from both
  sides; this one drives real events through `CatalogEvents.handle/4` and
  refutes any sentinel value in the captured stream.

  A vocabulary rejection at compile-time is not a log-safety proof. A future
  framework upgrade, a stray `Logger.debug/1` in a middleware, a telemetry
  handler that dumps payload metadata, or an Ecto binding under a
  parameterized query could all still emit a rejected key or its value at
  runtime.

  Surfaces sampled here (union of all three is the "combined stream"):

    * `ExUnit.CaptureLog.capture_log/1` — every `Logger` call at any level.
    * `ExUnit.CaptureIO.with_io/1` — `:stdio`, so a stray `IO.inspect/1`,
      `dbg/1`, or `IO.puts/1` a developer left on the events edge would
      surface as a leak. `capture_log` alone would not see it.
    * `ExUnit.CaptureIO.with_io(:stderr, …)` — same, for anything written
      directly to `:standard_error` (raw `IO.puts(:stderr, …)`, `IO.warn/1`,
      or a console backend misconfigured to write there).
    * A `:telemetry.attach_many/4` handler on every currently-emitted
      `[:dos, :catalog, …]` event that forwards each event's measurements
      and metadata into `:stdio` as a synthetic line. Telemetry metadata
      is a legitimate but potentially-leaky surface: a regression that
      stuffs selector values into `:query,:stop` metadata (thinking it's
      an internal channel) would surface the sentinel here.

  Path:

    1. Drive `catalog:select_year → select_make → select_model →
       select_configuration` events with sentinel personal identifiers
       (`vin`, `odometer`, `vehicle_id`, plus the personal-namespace
       trio `tab_id`, `notes`, `nickname`) embedded as extra payload
       keys — the CatalogEvents allowlist (`reject_extra_keys/2`) rejects
       the whole payload before `RateLimit.take/3`, `Selector.validate/2`,
       or any facade dispatch runs. The sentinels never reach the catalog
       facade at all.
    2. Fire a rate-limited call (empty bucket, valid shape carrying a
       distinctive `make_id` sentinel) — asserts the rate-limit error
       path emits no selector value.
    3. Fire a stale-cursor call (from the `cursor_test.exs` fixture
       pattern: encode a valid cursor, replace the `data_version` with a
       distinctive sentinel, re-encode) driven through the facade — the
       decoded stale-cursor error must reach the combined stream as an
       atom only, never the cursor binary or its decoded sentinel.

  `capture_log` with its default `level: nil` temporarily enables every
  Logger level for the duration of the function, so `:debug` output the
  test env's `:warning` filter would normally drop is still captured — a
  developer who dropped a `Logger.debug(inspect: params)` into the events
  edge or a telemetry handler during debugging would trip this.
  """
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{Cursor, RateLimit, Selector}
  alias DigitalOilStickerWeb.CatalogEvents

  # Sentinels chosen to be visually and structurally unmistakable. A real
  # VIN pattern (never a fixture value), a specific 6-digit odometer, and
  # a UUID with a distinctive nibble pattern. If any of these three strings
  # appears in the combined stream, a personal identifier crossed the
  # boundary.
  @vin "1HGBH41JXMN109186"
  @odometer "999888"
  @vehicle_id "77777777-7777-4777-8777-777777777777"

  # Additional personal-namespace sentinels. `tab_id` is a per-browser-tab
  # correlation id — not a user identifier on its own, but a fingerprinting
  # signal we do not want in any log or telemetry payload. `notes` and
  # `nickname` are free-text personal fields that must never surface.
  # Each carries a distinctive `nb17q` token so a partial dump that
  # truncates the string still fails the refute.
  @tab_id "sentinel-tab-nb17q-9f2e1a"
  @notes "sentinel-notes-nb17q kyler drives too fast do not log this"
  @nickname "sentinel-nickname-nb17q the daily beater"

  # A distinctive make_id embedded in the rate-limited call's params. The
  # rate-limit path returns `{:error, :rate_limited, bucket}` without
  # dispatching, but if a handler dumps the payload on the failure
  # this string will surface. Meets the catalog_id regex ^[a-z0-9-]{1,64}$
  # so `Selector.validate/2` would accept it in principle — the point is
  # that validate is never reached.
  @rate_limit_selector_marker "sentinel-rl-marker-nb17q"

  # A distinctive fake data_version stamped INTO the stale cursor's decoded
  # payload. If any layer decodes the cursor and dumps components, this
  # will surface. And if a layer echoes the base64 cursor binary itself,
  # `@stale_cursor_binary` (built inside the test) will catch that too.
  @stale_cursor_data_version_marker "sentinel-sc-marker-nb17q"

  # Every `[:dos, :catalog, …]` event currently emitted by the catalog
  # namespace. Telemetry does not support wildcard subscription; this is
  # the explicit enumeration a `[:dos, :catalog, :_]` subscription would
  # expand to. Add new events here if the catalog gains them — a
  # forgotten event is a hole in this test, not a hole in the invariant.
  @catalog_telemetry_events [
    [:dos, :catalog, :query, :start],
    [:dos, :catalog, :query, :stop],
    [:dos, :catalog, :query, :exception],
    [:dos, :catalog, :cache],
    [:dos, :catalog, :unavailable]
  ]

  test "no CatalogEvents chain or stale-cursor/rate-limit error path leaks a sentinel into logs" do
    bucket = RateLimit.new()

    # Build the stale cursor once, outside the capture wrappers, so the
    # encode step (which touches Metadata to stamp the current
    # data_version) is not itself part of the captured surface.
    {:ok, encode_sel} = Selector.validate(:list_makes, %{"year" => 2024})
    fresh_cursor = Cursor.encode(["some-marker", 42], encode_sel)

    stale_cursor_binary =
      fresh_cursor
      |> Base.url_decode64!(padding: false)
      |> JSON.decode!()
      |> List.replace_at(1, @stale_cursor_data_version_marker)
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    {:ok, stale_sel} =
      Selector.validate(:list_makes, %{"year" => 2024, "cursor" => stale_cursor_binary})

    # A unique-per-run handler id so parallel test runs (this file is
    # async: true) don't collide on the telemetry handler registry.
    handler_id = "log-scan-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      @catalog_telemetry_events,
      fn event, measurements, metadata, _config ->
        # Forward into :stdio, which the surrounding `with_io/1` wrapper
        # captures. Using `inspect/1` (not the raw term) so binaries with
        # sentinel content survive as-is into the stream instead of being
        # collapsed by any implicit protocol.
        IO.puts(
          "telemetry-forward event=" <>
            inspect(event) <>
            " measurements=" <>
            inspect(measurements) <>
            " metadata=" <>
            inspect(metadata)
        )
      end,
      nil
    )

    try do
      # Nesting order: `capture_log` is innermost so its scope is only the
      # test body; `with_io/1` captures :stdio (including the telemetry
      # forwarder's `IO.puts/1`); `with_io(:stderr, ...)` captures anything
      # written directly to :standard_error. Each `with_io` returns
      # `{result, captured}`; unpacking peels those two layers off in
      # outer-first order.
      {{log, stdout_captured}, stderr_captured} =
        with_io(:stderr, fn ->
          with_io(fn ->
            capture_log(fn ->
              # 1. select_year with sentinels: allowlist is ["year"]; the
              #    extra `vin`/`odometer`/`vehicle_id`/`tab_id`/`notes`/
              #    `nickname` keys collapse the whole payload via
              #    `reject_extra_keys/2` BEFORE the token bucket is spent
              #    and before Selector.validate/2 or any facade dispatch
              #    runs. The bucket must be returned unspent.
              assert {:error, :invalid_selector, ^bucket} =
                       CatalogEvents.handle(
                         "catalog:select_year",
                         %{
                           "year" => 2024,
                           "vin" => @vin,
                           "odometer" => @odometer,
                           "vehicle_id" => @vehicle_id,
                           "tab_id" => @tab_id,
                           "notes" => @notes,
                           "nickname" => @nickname
                         },
                         bucket,
                         0
                       )

              # A CLEAN select_year immediately after — this actually
              # reaches the facade and runs the underlying
              # `Identity.years/0` / `Identity.makes_page/1` queries. A
              # log line or telemetry event emitted here would carry the
              # shape of a valid call; the sentinels must not accidentally
              # survive from the prior rejected call in any
              # process-dictionary/metadata bag.
              assert {:ok, _makes, bucket1} =
                       CatalogEvents.handle(
                         "catalog:select_year",
                         %{"year" => 2024},
                         bucket,
                         0
                       )

              assert bucket1.tokens < bucket.tokens

              # 2. select_make with sentinels: allowlist is
              #    ["year", "make_id"]. Same rejection shape; the
              #    sentinels are extra keys.
              assert {:error, :invalid_selector, ^bucket1} =
                       CatalogEvents.handle(
                         "catalog:select_make",
                         %{
                           "year" => 2024,
                           "make_id" => "toyota",
                           "vin" => @vin,
                           "odometer" => @odometer,
                           "vehicle_id" => @vehicle_id,
                           "tab_id" => @tab_id,
                           "notes" => @notes,
                           "nickname" => @nickname
                         },
                         bucket1,
                         10
                       )

              # 3. select_model with sentinels: allowlist is
              #    ["year", "make_id", "model_id"]. Same rejection shape.
              assert {:error, :invalid_selector, ^bucket1} =
                       CatalogEvents.handle(
                         "catalog:select_model",
                         %{
                           "year" => 2024,
                           "make_id" => "toyota",
                           "model_id" => "camry",
                           "vin" => @vin,
                           "odometer" => @odometer,
                           "vehicle_id" => @vehicle_id,
                           "tab_id" => @tab_id,
                           "notes" => @notes,
                           "nickname" => @nickname
                         },
                         bucket1,
                         20
                       )

              # 4. select_configuration with sentinels: allowlist is
              #    ["configuration_key"]. Same rejection shape.
              assert {:error, :invalid_selector, ^bucket1} =
                       CatalogEvents.handle(
                         "catalog:select_configuration",
                         %{
                           "configuration_key" => "some-config-key",
                           "vin" => @vin,
                           "odometer" => @odometer,
                           "vehicle_id" => @vehicle_id,
                           "tab_id" => @tab_id,
                           "notes" => @notes,
                           "nickname" => @nickname
                         },
                         bucket1,
                         30
                       )

              # 5. Rate-limited call: empty bucket + a payload that is
              #    ALLOWLIST-VALID and carries a distinctive `make_id`
              #    marker. `RateLimit.take/3` fires and returns
              #    `{:error, :rate_limited, bucket}` before
              #    Selector.validate/2 or dispatch. Any log line or
              #    telemetry payload here must be shape-only
              #    ("rate_limited"), never a dump of `params` or the
              #    selector.
              empty = %RateLimit{RateLimit.new(1, 1, 0) | tokens: 0.0}

              assert {:error, :rate_limited, ^empty} =
                       CatalogEvents.handle(
                         "catalog:select_make",
                         %{"year" => 2024, "make_id" => @rate_limit_selector_marker},
                         empty,
                         0
                       )

              # 6. Stale-cursor call: driven at the facade seam, because
              #    none of the four `catalog:select_*` events accept a
              #    `cursor` payload key (verified against
              #    Vocabulary.event_allowlist/0). The facade routes
              #    through `Identity.makes_page/1` → `maybe_after/3` →
              #    `Cursor.decode/2`, which fails at the data_version
              #    comparison and returns `{:error, :stale_cursor}`. A
              #    log line or telemetry payload for this failure must
              #    carry the error atom and the function shape — never
              #    the cursor binary and never the decoded sentinel.
              assert {:error, :stale_cursor} = Catalog.list_makes(stale_sel)
            end)
          end)
        end)

      # Concatenate every captured surface into one string. All refutes
      # run against this union so a leak on ANY of {Logger, :stdio,
      # :stderr, telemetry metadata} fails the test.
      combined =
        Enum.join(
          [log, stdout_captured, stderr_captured],
          "\n"
        )

      # --- The three primary sentinels: extra-key values that must never
      # --- reach the combined stream by any path.
      refute combined =~ @vin,
             "combined stream carries the VIN sentinel — a CatalogEvents rejection path dumped a payload value"

      refute combined =~ @odometer,
             "combined stream carries the odometer sentinel — a CatalogEvents rejection path dumped a payload value"

      refute combined =~ @vehicle_id,
             "combined stream carries the vehicle_id UUID sentinel — a CatalogEvents rejection path dumped a payload value"

      # --- The additional personal-namespace sentinels: tab_id, notes,
      # --- nickname. These live in the payloads on the same rejection
      # --- path but are separate personal-identifier surfaces.
      refute combined =~ @tab_id,
             "combined stream carries the tab_id sentinel — a rejection path or telemetry handler dumped a payload value"

      refute combined =~ @notes,
             "combined stream carries the notes sentinel — a rejection path or telemetry handler dumped a payload value"

      refute combined =~ @nickname,
             "combined stream carries the nickname sentinel — a rejection path or telemetry handler dumped a payload value"

      # The extra KEY NAMES themselves are also personal-namespace signals.
      # A dump of `Map.keys(params)` on rejection would surface these even
      # if the values were redacted.
      refute combined =~ "\"vin\"",
             "combined stream carries the rejected key name `vin` — a rejection path dumped payload keys"

      refute combined =~ "\"odometer\"",
             "combined stream carries the rejected key name `odometer` — a rejection path dumped payload keys"

      refute combined =~ "\"vehicle_id\"",
             "combined stream carries the rejected key name `vehicle_id` — a rejection path dumped payload keys"

      refute combined =~ "\"tab_id\"",
             "combined stream carries the rejected key name `tab_id` — a rejection path dumped payload keys"

      refute combined =~ "\"notes\"",
             "combined stream carries the rejected key name `notes` — a rejection path dumped payload keys"

      refute combined =~ "\"nickname\"",
             "combined stream carries the rejected key name `nickname` — a rejection path dumped payload keys"

      # --- The rate-limited error path must not carry selector values.
      refute combined =~ @rate_limit_selector_marker,
             "combined stream carries the rate-limited call's selector marker — the rate-limit error path dumped params"

      # --- The stale-cursor error path must carry only the error atom
      # --- and function shape, not the cursor binary or its decoded payload.
      refute combined =~ @stale_cursor_data_version_marker,
             "combined stream carries the stale cursor's decoded sentinel — the stale-cursor error path decoded and logged the cursor"

      refute combined =~ stale_cursor_binary,
             "combined stream carries the raw stale-cursor base64 binary — the stale-cursor error path dumped the selector"
    after
      # Always detach, even on assertion failure inside `try`, so a
      # failing run does not leak a handler into subsequent tests.
      :telemetry.detach(handler_id)
    end
  end
end
