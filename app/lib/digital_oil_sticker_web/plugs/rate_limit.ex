defmodule DigitalOilStickerWeb.Plugs.RateLimit do
  @moduledoc """
  Per-IP HTTP token-bucket rate limit (DOS-M09-007 AC-6).

  Keys buckets by the hashed client identifier that
  `DigitalOilStickerWeb.Plugs.ClientIP` produces — never the raw address, and
  never anything the caller can rotate on demand (INV-26). Buckets live in a
  named ETS table owned by `DigitalOilStickerWeb.Plugs.RateLimitStore`, which
  is what keeps them alive across requests without leaking one process per
  caller.

  ## Why an ETS table, not the socket's own assigns

  Requests are not connections. Two HTTP requests from the same caller are
  handled by two separate processes, so a bucket held in one request's
  memory can only limit that request. The `DigitalOilSticker.Catalog.RateLimit`
  struct is per-socket by design and is the right primitive there — this plug
  covers the different problem of the initial HTTP call, before any socket
  exists.

  ## The refill formula

  For each request:

      elapsed_s = max(now_ms - updated_ms, 0) / 1000
      available = min(tokens + elapsed_s * refill_per_second, capacity)

  A caller with a full bucket gets `capacity` requests before any refill
  matters; a caller who has been silent long enough refills back to
  `capacity` but no further. If `available` is at least one token, one is
  consumed and the request continues. Otherwise the response is `429` and
  the plug halts — no router, no LiveView mount, no cache read.

  The rejection body is empty on purpose: the caller's address is what the
  bucket is keyed on, and the whole point of the ClientIP hash is that the
  address never leaves memory. A 429 that echoes "203.0.113.9 is rate
  limited" undoes it on the one response most likely to be captured verbatim
  in a screenshot or bug report.

  ## Read-modify-write is racy on purpose

  This does a lookup and a subsequent insert, not an atomic decrement. Under
  contention two callers can each see an available bucket and each be
  granted a token that strictly one should have — but the excess is bounded
  by the number of concurrently racing schedulers, not by traffic, and a
  bucket that is actually empty stays empty for every racing caller alike.
  An atomic counter would cost either the fractional refill (integer
  counters only) or a serializing GenServer hop, which is the bottleneck
  this plug exists to avoid.

  ## Rejected callers still refresh the bucket

  On a rejection the entry is still rewritten with the refilled `available`
  and the current `updated_ms`. Without that step, a bucket that missed its
  refill window would carry a stale `updated_ms` forward and its next
  request would credit the elapsed time twice — once now, once next call.

  ## Options and seams

  Init opts:

    * `:capacity` — burst size, positive integer. Default `60`.
    * `:refill_per_second` — token refill rate, positive number. Default `1`.
    * `:table` — the named ETS table to use. Default:
      `RateLimitStore.table()`. Passed explicitly by tests so they get their
      own table per test rather than sharing the process-wide one.
    * `:now_fun` — zero-arity function returning the current time in
      milliseconds. Default: `System.monotonic_time/1` at `:millisecond`.
      Overridden by tests so the refill assertion does not need to sleep.

  What init receives wins, unconditionally. What init did not receive falls
  back to a per-call read of
  `config :digital_oil_sticker, DigitalOilStickerWeb.Plugs.RateLimit, ...`,
  then to the defaults above. That precedence is what lets the test env hold
  `:capacity` at a value the whole suite's `127.0.0.1` traffic cannot drain,
  while the isolated plug test still gets the explicit `capacity: 3` it
  passed to `init/1`.
  """
  @behaviour Plug

  import Plug.Conn

  alias DigitalOilStickerWeb.Plugs.{ClientIP, RateLimitStore}

  @default_capacity 60
  @default_refill_per_second 1

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts) when is_list(opts) do
    if val = Keyword.get(opts, :capacity), do: validate_capacity!(val)
    if val = Keyword.get(opts, :refill_per_second), do: validate_refill!(val)

    Keyword.take(opts, [:capacity, :refill_per_second, :table, :now_fun])
  end

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    {capacity, refill, table, now_fun} = resolve(opts)
    now_ms = now_fun.()
    key = client_key(conn)

    case take(table, key, capacity, refill, now_ms) do
      :ok ->
        conn

      {:rate_limited, retry_after_s} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_s))
        |> send_resp(429, "")
        |> halt()
    end
  end

  # Explicit init opts win over Application env, which wins over module
  # defaults. The distinction matters: the endpoint installs this plug with
  # no opts and expects the test env's Application override to raise the
  # limit; the isolated plug test installs it with `capacity: 3` and expects
  # exactly three tokens no matter what config says.
  defp resolve(opts) do
    overrides = Application.get_env(:digital_oil_sticker, __MODULE__, [])

    capacity =
      Keyword.get_lazy(opts, :capacity, fn ->
        Keyword.get(overrides, :capacity, @default_capacity)
      end) * 1.0

    refill =
      Keyword.get_lazy(opts, :refill_per_second, fn ->
        Keyword.get(overrides, :refill_per_second, @default_refill_per_second)
      end) * 1.0

    table = Keyword.get_lazy(opts, :table, &RateLimitStore.table/0)
    now_fun = Keyword.get(opts, :now_fun, &default_now/0)

    {capacity, refill, table, now_fun}
  end

  defp default_now, do: System.monotonic_time(:millisecond)

  # Prefer the assign the ClientIP plug already computed; fall back to
  # computing it here so a misconfiguration produces a real key rather than a
  # crash that skips the limit entirely.
  defp client_key(conn) do
    case conn.assigns do
      %{client_key: key} when is_binary(key) -> key
      _ -> ClientIP.client_key(conn)
    end
  end

  defp take(table, key, capacity, refill, now_ms) do
    {tokens, updated_ms} =
      case :ets.lookup(table, key) do
        [{^key, %{tokens: t, updated_ms: u}}] -> {t, u}
        [] -> {capacity, now_ms}
      end

    elapsed_s = max(now_ms - updated_ms, 0) / 1000
    available = min(tokens + elapsed_s * refill, capacity)

    if available >= 1.0 do
      :ets.insert(table, {key, %{tokens: available - 1.0, updated_ms: now_ms}})
      :ok
    else
      :ets.insert(table, {key, %{tokens: available, updated_ms: now_ms}})
      # Whole seconds are what clients honor; round up so we never advise a
      # retry before a token would actually be available.
      retry_after_s = max(ceil((1.0 - available) / refill), 1)
      {:rate_limited, retry_after_s}
    end
  end

  defp validate_capacity!(val) do
    unless is_integer(val) and val > 0 do
      raise ArgumentError,
            ":capacity must be a positive integer, got #{inspect(val)}"
    end
  end

  defp validate_refill!(val) do
    unless is_number(val) and val > 0 do
      raise ArgumentError,
            ":refill_per_second must be a positive number, got #{inspect(val)}"
    end
  end
end
