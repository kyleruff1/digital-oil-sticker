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

  ## Multiple buckets

  Started with `name: SomeAtom` the store runs as that name and owns an
  ETS table of the same name. The default is the module name, keeping
  the loose `/api/v1/*` bucket's wiring untouched. A second instance
  (e.g. the strict `/from-text` bucket) is started in the supervision
  tree under a distinct name, and the plug receives it via `table:`
  init opt.
  """
  use GenServer

  @default_name __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc """
  Supervisor-friendly child spec that keys the child id by the bucket
  name, so two buckets can live side by side under one supervisor.
  """
  def child_spec(opts) do
    name = Keyword.get(opts, :name, @default_name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc "Named table for direct access from the plug's latency path (default bucket)."
  @spec table() :: atom()
  def table, do: @default_name

  @impl true
  def init(name) do
    :ets.new(name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{name: name}}
  end
end
