defmodule DigitalOilSticker.Catalog.Cache do
  @moduledoc """
  Read-through result cache. Keys are `{data_version, canonical_selector}` —
  derived only from the validated Selector, which structurally cannot hold
  client free text, so no client-derived value can enter a key. Only
  successful results are cached (errors are never promoted to authoritative).
  Two-generation eviction: O(1), no per-read writes on the latency path.
  Reads run in the caller off ETS; the GenServer only owns rotation.
  """
  use GenServer
  alias DigitalOilSticker.Catalog.{Metadata, Selector}

  @young __MODULE__.Young
  @old __MODULE__.Old
  @max_entries_per_generation 5_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@young, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@old, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @spec fetch(atom(), Selector.t(), (-> {:ok, term()} | {:error, atom()})) ::
          {:ok, term()} | {:error, atom()}
  def fetch(function, %Selector{} = sel, fun) do
    key = key(function, sel)

    case lookup(key) do
      {:ok, value} ->
        :telemetry.execute([:dos, :catalog, :cache], %{hit: 1}, %{function: function})
        {:ok, value}

      :miss ->
        :telemetry.execute([:dos, :catalog, :cache], %{miss: 1}, %{function: function})

        case fun.() do
          {:ok, value} = ok ->
            put(key, value)
            ok

          error ->
            error
        end
    end
  end

  def key(function, %Selector{} = sel) do
    canonical =
      sel
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.sort()

    {Metadata.data_version(), function, canonical}
  end

  defp lookup(key) do
    case :ets.lookup(@young, key) do
      [{^key, value}] ->
        {:ok, value}

      [] ->
        case :ets.lookup(@old, key) do
          [{^key, value}] ->
            # Promote on old-generation hit (single write, off the common path).
            :ets.insert(@young, {key, value})
            {:ok, value}

          [] ->
            :miss
        end
    end
  end

  defp put(key, value) do
    :ets.insert(@young, {key, value})

    if :ets.info(@young, :size) > @max_entries_per_generation,
      do: GenServer.cast(__MODULE__, :rotate)

    :ok
  end

  @impl true
  def handle_cast(:rotate, state) do
    :ets.delete_all_objects(@old)
    # Move young -> old wholesale; young starts empty.
    :ets.foldl(fn entry, _ -> :ets.insert(@old, entry) end, nil, @young)
    :ets.delete_all_objects(@young)
    {:noreply, state}
  end

  @doc "Test/inspection helper."
  def stats do
    %{young: :ets.info(@young, :size), old: :ets.info(@old, :size)}
  end
end
