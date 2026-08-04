defmodule DigitalOilStickerWeb.SocketConnectLimitTest do
  @moduledoc """
  The per-client concurrent-connect ceiling for the LiveView socket
  (DOS-M09-007 FR-8, INV-26 AC-6-socket) — **module-level only**.

  ## Honest scope

  This suite proves the `ConnectLimiter` module's arithmetic and keying are
  correct: the counter increments, refuses at the ceiling, rolls back a
  refused attempt, clamps release at zero, isolates keys per client, and
  honours a custom limit. That is the "does the ceiling work" half.

  What it does **not** prove is the "is the ceiling actually consulted on a
  real socket connect" half. As of this commit, `ConnectLimiter.try_connect/2`
  has zero callers in the production code path — grep the app tree and only
  this test file appears. A per-client concurrent-connect limit that no
  socket connect calls is a correct module and a missing control.

  The gap exists because `Phoenix.LiveView.Socket` (the module the endpoint
  installs at `"/live"`) does not accept a user-defined `connect/3`
  callback the way `Phoenix.Socket` does, so the natural hook point is not
  where a Phoenix.Socket example would put it. Wiring into the real socket
  connect is deferred pending one of:

    * a `Phoenix.LiveView.Socket` connect hook (upstream);
    * a custom socket module wrapping `Phoenix.LiveView.Socket` at
      `"/live"`;
    * an `on_mount` hook that calls `try_connect_for/2` when
      `Phoenix.LiveView.connected?(socket)` is true, plus a monitor that
      calls `release/1` when the LV process terminates.

  Until then, the enforced HTTP-side of AC-6 (per-IP rate limit against the
  initial LiveView boot GET, which every WebSocket upgrade must be preceded
  by for the CSRF token) is asserted end-to-end in
  `DigitalOilStickerWeb.LiveBootRateLimitTest`. Followup for the socket-side
  wiring is tracked separately.

  ## Failure mode this module (if wired) would catch

  One script opening enough sockets to crowd out every other visitor. Without
  a bound, `n` tabs from one browser cost the server `n` process trees, one
  heap each, and nothing pushes back. The limit is a numeric ceiling per
  `ClientIP.client_key/1`; the moment a new socket would carry the count
  past that ceiling, the connect is refused.

  `async: false` because the ETS table is process-global by name; a
  concurrent suite writing to the same table would race the counts and mask
  a real bug in the ceiling logic behind an interleaving.
  """
  use ExUnit.Case, async: false

  alias DigitalOilStickerWeb.ConnectLimiter

  @limit 20
  @client_a "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @client_b "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  setup do
    # The module lives in the application supervision tree, so its ETS table
    # is already up — reset the counts each test rather than restart the
    # process, since a restart would race the supervisor.
    ConnectLimiter.reset()
    on_exit(fn -> ConnectLimiter.reset() end)
    :ok
  end

  test "the default limit is the ceiling the rest of this file is written around" do
    # If someone later widens or tightens the default, the number every
    # assertion below is built around needs to change with it.
    assert ConnectLimiter.default_limit() == @limit
  end

  test "the first `limit` sequential connects from one client all succeed" do
    for i <- 1..@limit do
      assert ConnectLimiter.try_connect(@client_a, @limit) == :ok,
             "connect #{i} was refused; the ceiling is #{@limit}, so a legitimate visitor was turned away"
    end

    assert ConnectLimiter.count(@client_a) == @limit
  end

  test "the `limit + 1`-th connect from the same client is refused" do
    for _ <- 1..@limit, do: :ok = ConnectLimiter.try_connect(@client_a, @limit)

    assert ConnectLimiter.try_connect(@client_a, @limit) ==
             {:error, :too_many_connections}

    # The refused connect must not count toward the ceiling — if it did, one
    # over-limit attempt would silently lower the ceiling for every following
    # legitimate call from the same client.
    assert ConnectLimiter.count(@client_a) == @limit
  end

  test "releasing a slot lets the next connect through again" do
    for _ <- 1..@limit, do: :ok = ConnectLimiter.try_connect(@client_a, @limit)

    assert ConnectLimiter.try_connect(@client_a, @limit) ==
             {:error, :too_many_connections}

    :ok = ConnectLimiter.release(@client_a)

    assert ConnectLimiter.try_connect(@client_a, @limit) == :ok
    assert ConnectLimiter.count(@client_a) == @limit
  end

  test "two clients keep independent counts" do
    # Saturate A completely so the shared-table hypothesis has something to
    # bleed from.
    for _ <- 1..@limit, do: :ok = ConnectLimiter.try_connect(@client_a, @limit)

    assert ConnectLimiter.try_connect(@client_a, @limit) ==
             {:error, :too_many_connections}

    # B has never connected — a shared counter would already have refused it.
    for i <- 1..@limit do
      assert ConnectLimiter.try_connect(@client_b, @limit) == :ok,
             "client B was refused at slot #{i} — the counter is bleeding between clients"
    end

    assert ConnectLimiter.count(@client_a) == @limit
    assert ConnectLimiter.count(@client_b) == @limit
  end

  test "release clamps at zero, so a duplicate release cannot loosen the ceiling" do
    # A close handler that fires twice (a crash cleaned up by both the socket
    # and the transport) must not gift the client a free slot on top of the
    # ceiling.
    :ok = ConnectLimiter.try_connect(@client_a, @limit)
    :ok = ConnectLimiter.release(@client_a)
    :ok = ConnectLimiter.release(@client_a)

    assert ConnectLimiter.count(@client_a) == 0

    for _ <- 1..@limit, do: :ok = ConnectLimiter.try_connect(@client_a, @limit)

    assert ConnectLimiter.try_connect(@client_a, @limit) ==
             {:error, :too_many_connections}
  end

  test "custom limits are honored, so a caller can enforce a stricter ceiling" do
    # The default is deliberately the loosest ceiling. A code path that needs
    # tighter — a specific transport, a specific route — must be able to pass
    # a smaller number and have it stick.
    tight = 3

    for _ <- 1..tight, do: :ok = ConnectLimiter.try_connect(@client_a, tight)

    assert ConnectLimiter.try_connect(@client_a, tight) ==
             {:error, :too_many_connections}
  end

  test "try_connect_for/2 keys off the same client hash the socket connect uses" do
    conn_a = %{Phoenix.ConnTest.build_conn() | remote_ip: {203, 0, 113, 10}}
    conn_b = %{Phoenix.ConnTest.build_conn() | remote_ip: {203, 0, 113, 11}}

    for _ <- 1..@limit, do: :ok = ConnectLimiter.try_connect_for(conn_a, @limit)

    assert ConnectLimiter.try_connect_for(conn_a, @limit) ==
             {:error, :too_many_connections}

    # A different IP resolves to a different key, so its budget is untouched
    # by A's saturation — which is exactly the property a per-client ceiling
    # exists to provide, asserted through the same key-derivation path a real
    # socket connect uses.
    assert ConnectLimiter.try_connect_for(conn_b, @limit) == :ok
  end
end
