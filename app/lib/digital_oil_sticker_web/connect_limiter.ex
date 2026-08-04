defmodule DigitalOilStickerWeb.ConnectLimiter do
  @moduledoc """
  Per-client concurrent-connect ceiling for the LiveView socket
  (DOS-M09-007 FR-8, INV-26).

  A single ETS counter table, one row per client key. `try_connect/2`
  atomically increments the count and returns `{:error, :too_many_connections}`
  (rolling the increment back) the moment it would exceed `limit`; `release/1`
  is what a closing socket calls to drop the count.

  ## Why per-client, not per-node

  A single misbehaving script is not a load problem — a fleet-wide flood is.
  A per-node concurrent-connect ceiling that spans all clients would either be
  too high to catch one client's abuse, or low enough to break under a
  legitimate traffic spike. Keying on `ClientIP.client_key/1` bounds one
  client's damage without touching the aggregate.

  ## Why an ETS counter, not a queue or a GenServer per key

  All the work is `:ets.update_counter/4`, which is an atomic RMW inside the
  Erlang VM — no message send, no per-key process, and the counter has no
  memory of *which* connects are open, only *how many*. That is exactly enough
  to enforce a ceiling and refuses to become a session identifier (INV-26).
  The key itself is already the salted hash `ClientIP.client_key/1` produces,
  so nothing that could reach an address ever lives in the table.

  ## The hook point the socket connect passes through

  The Phoenix.LiveView socket handshake reaches this module through
  `try_connect/2` at connect time; a matching `release/1` runs when the
  socket process terminates. Callers pass the key derived by
  `DigitalOilStickerWeb.Plugs.ClientIP.client_key/1`. This module owns the
  count; the socket-connect refusal is derived from the metric this module
  produces, which is what the accompanying test asserts.
  """
  use GenServer

  alias DigitalOilStickerWeb.Plugs.ClientIP

  @table __MODULE__
  @default_limit 20

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    {:ok, %{}}
  end

  @doc """
  Claim one concurrent-connect slot for `key`. Returns `:ok` if the count
  after the claim is `<= limit`; otherwise rolls the claim back and returns
  `{:error, :too_many_connections}` so a refused connect never counts toward
  the ceiling.
  """
  @spec try_connect(binary(), pos_integer()) :: :ok | {:error, :too_many_connections}
  def try_connect(key, limit \\ @default_limit)
      when is_binary(key) and is_integer(limit) and limit > 0 do
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if count > limit do
      # Symmetric roll-back so the transient over-count vanishes as soon as
      # this call returns — without it, one refused attempt would silently
      # lower the ceiling for every following legitimate call.
      :ets.update_counter(@table, key, {2, -1, 0, 0})
      {:error, :too_many_connections}
    else
      :ok
    end
  end

  @doc """
  Release one slot for `key`. Decrements clamp at zero so a duplicate release
  (a close handler firing twice, a crashed process cleaned up twice) cannot
  push the count negative and gift the client a free slot.
  """
  @spec release(binary()) :: :ok
  def release(key) when is_binary(key) do
    :ets.update_counter(@table, key, {2, -1, 0, 0}, {key, 0})
    :ok
  end

  @doc "Current concurrent-connect count for `key`. Zero if never seen."
  @spec count(binary()) :: non_neg_integer()
  def count(key) when is_binary(key) do
    case :ets.lookup(@table, key) do
      [{^key, n}] -> n
      [] -> 0
    end
  end

  @doc "The compiled-in default ceiling — the number the tests exercise."
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  Convenience for callers that already have a `Plug.Conn` — resolves the key
  through the same `ClientIP.client_key/1` the socket connect uses, so a test
  and a real handshake bucket the same client to the same row.
  """
  @spec try_connect_for(Plug.Conn.t(), pos_integer()) ::
          :ok | {:error, :too_many_connections}
  def try_connect_for(%Plug.Conn{} = conn, limit \\ @default_limit) do
    try_connect(ClientIP.client_key(conn), limit)
  end

  @doc """
  Test hygiene: drop every count. Do not call from production paths — an
  empty table means every client's ceiling is briefly reset to zero-used.
  """
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end
end
