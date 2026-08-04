defmodule DigitalOilStickerWeb.Plugs.RateLimitStore do
  @moduledoc """
  Owns the ETS table that backs `DigitalOilStickerWeb.Plugs.RateLimit`
  (DOS-M09-007 AC-6).

  The plug does the work — the lookup and the write — against the table
  directly, so the latency path is a single scheduler with no GenServer hop.
  This process exists only to own the table's lifetime.

  ETS tables die with their owner. A plug-owned table would vanish the
  moment any request that touched it crashed, and a per-request process
  would leak one owner per request. Held here, the table survives every
  request and every request-process crash, and is only replaced if this
  supervisor child itself restarts — at which point every bucket resets,
  which is a fresh-boot condition callers must already tolerate.

  The stored value is `%{tokens: float, updated_ms: integer}`. Nothing else
  is kept per key — no address, no header, no request-shape — so the table
  cannot become a passive tracking store (INV-26).
  """
  use GenServer

  @table __MODULE__

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Named table for direct access from the plug's latency path."
  @spec table() :: atom()
  def table, do: @table

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end
end
