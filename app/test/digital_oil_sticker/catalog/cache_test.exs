defmodule DigitalOilSticker.Catalog.CacheTest do
  @moduledoc """
  AC-9: the four Cache invariants that make this a safe read path.

    (a) Only `{:ok, _}` results are cached — errors are never authoritative,
        so a transient failure cannot pin a wrong answer.
    (b) The key includes `data_version` from Metadata, so a catalog swap
        invalidates the entire cache structurally rather than being policed.
    (c) The two-generation ring evicts wholesale — young rotates into old and
        the prior old is dropped, keeping the operation O(1).
    (d) The key is derived only from a validated `%Selector{}` — the closed
        vocabulary means no client-supplied free text can ever enter a key.

  Not `async: true`: the Cache GenServer and its `Young`/`Old` ETS tables are
  singletons owned by the application supervisor, and one test overrides
  Metadata's `:persistent_term` entry — both are process-global state.
  """
  use ExUnit.Case, async: false

  alias DigitalOilSticker.Catalog.{Cache, Metadata, Selector, Vocabulary}

  @young Cache.Young
  @old Cache.Old

  setup do
    # Drain any queued rotation casts from a prior test, then clear both
    # generations so each test starts from a known-empty cache.
    :sys.get_state(Cache)
    :ets.delete_all_objects(@young)
    :ets.delete_all_objects(@old)
    :ok
  end

  test "fetch/3 caches successes; errors are never retained" do
    {:ok, sel} = Selector.validate(:list_makes, %{"year" => 2024})
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    counting = fn result ->
      fn ->
        Agent.update(counter, &(&1 + 1))
        result
      end
    end

    # An error result runs the fn but is not stored.
    assert {:error, :something} =
             Cache.fetch(:list_makes, sel, counting.({:error, :something}))

    assert Agent.get(counter, & &1) == 1

    # Because the prior error was not cached, the next fetch invokes again
    # — this time returning ok, which IS retained.
    assert {:ok, :real} = Cache.fetch(:list_makes, sel, counting.({:ok, :real}))
    assert Agent.get(counter, & &1) == 2

    # Subsequent fetches must serve from cache — the fn would raise if run.
    would_raise = fn -> raise "cache miss where a hit was required" end
    assert {:ok, :real} = Cache.fetch(:list_makes, sel, would_raise)
    assert {:ok, :real} = Cache.fetch(:list_makes, sel, would_raise)
    assert Agent.get(counter, & &1) == 2
  end

  test "the cache key includes data_version, so a metadata bump invalidates it" do
    {:ok, sel} = Selector.validate(:list_makes, %{"year" => 2024})
    original = Metadata.get()
    on_exit(fn -> :persistent_term.put({Metadata, :metadata}, original) end)

    :persistent_term.put({Metadata, :metadata}, %{original | data_version: "test-v1"})
    key_v1 = Cache.key(:list_makes, sel)

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(counter, &(&1 + 1))
      {:ok, :cached_value}
    end

    assert {:ok, :cached_value} = Cache.fetch(:list_makes, sel, fun)
    assert {:ok, :cached_value} = Cache.fetch(:list_makes, sel, fun)
    assert Agent.get(counter, & &1) == 1

    # Simulate a catalog swap: same map, only data_version changes.
    :persistent_term.put({Metadata, :metadata}, %{original | data_version: "test-v2"})
    key_v2 = Cache.key(:list_makes, sel)
    refute key_v1 == key_v2

    # The previously cached entry lives at the v1 key and must not be
    # returned under v2 — the fn must be invoked again.
    assert {:ok, :cached_value} = Cache.fetch(:list_makes, sel, fun)
    assert Agent.get(counter, & &1) == 2
  end

  test "young rotates into old and the prior generation drops on the second turn" do
    # Phase 1: insert past the 5_000 cap. Fabricated selectors bypass
    # Selector.validate (which enforces the metadata year window) — the
    # eviction path is what's under test here, not vocabulary validation.
    for y <- 1..5_001 do
      fake = %Selector{function: :list_makes, year: y}
      Cache.fetch(:list_makes, fake, fn -> {:ok, y} end)
    end

    # Drain any queued :rotate casts so we observe the settled state.
    :sys.get_state(Cache)

    stats1 = Cache.stats()
    assert stats1.young == 0
    assert stats1.old == 5_001

    # Phase 2: a disjoint 5_001-entry range triggers a second rotation.
    for y <- 100_000..105_000 do
      fake = %Selector{function: :list_makes, year: y}
      Cache.fetch(:list_makes, fake, fn -> {:ok, y} end)
    end

    :sys.get_state(Cache)

    stats2 = Cache.stats()
    assert stats2.young == 0
    assert stats2.old == 5_001

    # After the second rotation, phase-1 entries are gone from BOTH tables
    # — a refetch of a phase-1 selector must invoke the miss fn.
    phase1_sel = %Selector{function: :list_makes, year: 1}
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    refetch = fn ->
      Agent.update(counter, &(&1 + 1))
      {:ok, :re_derived}
    end

    assert {:ok, :re_derived} = Cache.fetch(:list_makes, phase1_sel, refetch)
    assert Agent.get(counter, & &1) == 1
  end

  test "keys are derived only from validated struct fields, never from raw input" do
    {:ok, sel} = Selector.validate(:list_makes, %{"year" => 2024, "page_size" => 50})
    {data_version, function, canonical} = Cache.key(:list_makes, sel)

    assert is_binary(data_version)
    assert function == :list_makes

    # Every key inside `canonical` is an atom drawn from the closed vocabulary
    # (plus :function itself). Selector.validate never calls String.to_atom,
    # so no client-provided string can become a key here.
    allowed = [:function | Vocabulary.all_fields()]

    for {k, _v} <- canonical do
      assert is_atom(k), "canonical key #{inspect(k)} must be an atom, not a raw string"
      assert k in allowed, "canonical key #{inspect(k)} must belong to the vocabulary"
    end

    # A client-invented key rejects the whole payload; it cannot enter the
    # struct, and therefore cannot enter the cache key at all.
    assert {:error, :invalid_selector} =
             Selector.validate(:list_makes, %{"year" => 2024, "client_marker_9f3" => "leak"})

    # Belt-and-braces: the marker byte-sequence does not appear anywhere in
    # the serialized key from the valid selector above.
    assert :nomatch =
             :binary.match(:erlang.term_to_binary(canonical), "client_marker_9f3")
  end
end
