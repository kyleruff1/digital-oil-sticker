defmodule DigitalOilSticker.Catalog.FailureModesTest do
  @moduledoc """
  DOS-M09-004 AC-7: fault-injection for `Catalog.guarded/2` and pairwise
  disjointness of the three caller-visible failure atoms.

  The facade contract (`t:DigitalOilSticker.Catalog.error/0`) is that a DB
  outage MUST surface as `{:error, :catalog_unavailable}` — the request
  process must NOT crash on a `DBConnection.ConnectionError` or
  `Exqlite.Error`. The rescue that guarantees this lives in the private
  `Catalog.guarded/2`; because it is private it can only be exercised by
  making a real underlying query raise, which is what this file does.

  Fault-injection technique: the fixture repo is unusable when its lone
  pool connection is held by another process AND the pool's CoDel drop is
  aggressive. We reconfigure `CatalogRepo` (pool_size: 1, queue_target: 1,
  queue_interval: 1), starve the pool with a held checkout, and then hit
  the facade. The queued checkout is dropped within ~1ms with a real
  `DBConnection.ConnectionError`, giving `guarded/2` a genuine exception
  to rescue — no mocking, no monkey-patching. Terminating the whole repo
  child instead raises `RuntimeError` from `Ecto.Repo.Registry.lookup`,
  which is out of scope of the current rescue and would incorrectly crash
  the caller, so it is not used here.

  Disjointness: caller-visible outcomes on the SAME `catalog:select_year`
  event surface with different atoms depending on which layer refused —
  `:rate_limited` (tier-1 bucket, before the facade runs),
  `:catalog_unavailable` (facade rescue), `:invalid_selector` (vocabulary
  rejection). INV-11 also requires that absent-fact statuses
  (`:unsupported`, `:not_applicable`, etc.) live in a disjoint namespace
  from these error atoms; this file asserts the four atoms it exercises
  are pairwise distinct.
  """
  # `async: false` because these tests reconfigure the CatalogRepo child
  # and restart it under `DigitalOilSticker.Supervisor`. Any concurrent
  # test that reads the catalog during that window would see spurious
  # errors from the reconfigured pool.
  use ExUnit.Case, async: false

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{RateLimit, Result, Selector}
  alias DigitalOilSticker.CatalogRepo
  alias DigitalOilStickerWeb.CatalogEvents

  @app_sup DigitalOilSticker.Supervisor
  @young_cache DigitalOilSticker.Catalog.Cache.Young
  @old_cache DigitalOilSticker.Catalog.Cache.Old

  describe "AC-7 part 1 — guarded/2 rescues real DB failures into :catalog_unavailable" do
    setup :starve_pool_setup

    test "with the pool starved, Catalog.list_years/1 returns {:error, :catalog_unavailable} rather than crashing" do
      # The success path caches on {:ok, _}. If a prior test cached
      # list_years, guarded/2 is never reached — clear both generations.
      clear_cache!()

      {:ok, sel} = Selector.validate(:list_years, %{})

      # The rescue in guarded/2 is the load-bearing assertion. If it did
      # not fire, this call would raise DBConnection.ConnectionError and
      # kill the test process — not return a tuple.
      assert {:error, :catalog_unavailable} = Catalog.list_years(sel)
    end

    test "the same rescue converts every selector-taking function's DB failure identically" do
      # Guardrail against a future refactor that adds a new facade
      # function without routing it through `call/3` (and thus without
      # guarded/2). If any of these crashes instead of returning
      # :catalog_unavailable, the rescue coverage is incomplete.
      clear_cache!()

      {:ok, years_sel} = Selector.validate(:list_years, %{})
      {:ok, makes_sel} = Selector.validate(:list_makes, %{"year" => 2024})

      assert {:error, :catalog_unavailable} = Catalog.list_years(years_sel)
      assert {:error, :catalog_unavailable} = Catalog.list_makes(makes_sel)
    end
  end

  describe "AC-7 part 2 — the caller-visible failure atoms are pairwise disjoint" do
    test "an unsupported status (:unsupported) is a Result, never an error atom, so it cannot collide" do
      # INV-11: absent facts are STATUSES on {:ok, %Result{}}, not errors.
      # `list_compatible_filters` with an unknown configuration key is the
      # canonical absent-fact case.
      fake = String.duplicate("0", 8) <> "-0000-5000-8000-" <> String.duplicate("0", 12)
      {:ok, sel} = Selector.validate(:list_compatible_filters, %{"configuration_key" => fake})

      assert {:ok, %Result{status: :unsupported}} = Catalog.list_compatible_filters(sel)
    end

    test "on identical input, rate-limit / catalog-unavailable / invalid-selector produce three distinct error atoms" do
      # Same event name + same input params in every scenario — only the
      # fault mode varies. This is the load-bearing check for INV-11's
      # "each failure has its own atom" contract at the web edge.
      event = "catalog:select_year"
      params = %{"year" => 2024}

      # -- rate-limited: repo up, bucket drained -----------------------
      drained = %RateLimit{RateLimit.new(1, 1, 0) | tokens: 0.0}

      assert {:error, :rate_limited, ^drained} =
               CatalogEvents.handle(event, params, drained, 0)

      # -- catalog-unavailable: repo pool starved, valid selector ------
      catalog_unavailable_atom =
        with_starved_pool(fn ->
          clear_cache!()

          case CatalogEvents.handle(event, params, RateLimit.new(30, 5, 0), 0) do
            {:error, atom, _bucket} -> atom
          end
        end)

      assert catalog_unavailable_atom == :catalog_unavailable

      # -- invalid-selector: repo up, one unknown key on the SAME event
      # (the payload is otherwise identical to the rate-limited case) --
      params_extra = Map.put(params, "vin", "X")

      assert {:error, :invalid_selector, _} =
               CatalogEvents.handle(event, params_extra, RateLimit.new(30, 5, 0), 0)

      # Pairwise disjoint = three DISTINCT atoms. The tuple form of the
      # assertion below fails loudly if two atoms ever collapse into one,
      # which would silently merge two failure modes into one caller
      # branch and violate INV-11.
      atoms = [:rate_limited, catalog_unavailable_atom, :invalid_selector]
      assert length(Enum.uniq(atoms)) == 3, "expected pairwise-disjoint atoms, got: #{inspect(atoms)}"

      # And the absent-fact status atom (:unsupported) must not collide
      # with any of the three error atoms — status and error are
      # separate namespaces per INV-11.
      refute :unsupported in atoms
    end
  end

  # -- helpers ---------------------------------------------------------

  # Wraps a function in the pool-starvation regime used by AC-7 part 1
  # and the disjointness check. Restores the original CatalogRepo config
  # and repo child on the way out — including when the caller raises.
  defp with_starved_pool(fun) do
    original_config = Application.get_env(:digital_oil_sticker, CatalogRepo)

    try do
      restart_repo_with!(
        Keyword.merge(original_config,
          pool_size: 1,
          queue_target: 1,
          queue_interval: 1
        )
      )

      parent = self()

      hold_task =
        Task.async(fn ->
          CatalogRepo.checkout(fn ->
            send(parent, :held)

            receive do
              :release -> :ok
            after
              5_000 -> :ok
            end
          end)
        end)

      assert_receive :held, 2_000

      # A brief pause so the pool's CoDel poll flips into "slow" state
      # (queue_interval = 1ms) — otherwise the first checkout may still
      # be waiting rather than dropped.
      Process.sleep(30)

      try do
        fun.()
      after
        send(hold_task.pid, :release)
        _ = Task.await(hold_task, 5_000)
      end
    after
      Application.put_env(:digital_oil_sticker, CatalogRepo, original_config)
      restart_repo_with!(original_config)
    end
  end

  # Setup form of the same regime for tests whose whole body runs under
  # a starved pool. We can't just wrap the body because ExUnit assertions
  # inside `with_starved_pool` would still exit early cleanly, but
  # readability improves when the fault regime is declared at the top.
  defp starve_pool_setup(_ctx) do
    original_config = Application.get_env(:digital_oil_sticker, CatalogRepo)

    restart_repo_with!(
      Keyword.merge(original_config,
        pool_size: 1,
        queue_target: 1,
        queue_interval: 1
      )
    )

    parent = self()

    hold_task =
      Task.async(fn ->
        CatalogRepo.checkout(fn ->
          send(parent, :held)

          receive do
            :release -> :ok
          after
            5_000 -> :ok
          end
        end)
      end)

    assert_receive :held, 2_000
    Process.sleep(30)

    on_exit(fn ->
      # Task.async link is scoped to the test process, which is gone by
      # the time on_exit runs — just send and forget, then restore.
      send(hold_task.pid, :release)
      Application.put_env(:digital_oil_sticker, CatalogRepo, original_config)
      restart_repo_with!(original_config)
    end)

    :ok
  end

  defp restart_repo_with!(config) do
    Application.put_env(:digital_oil_sticker, CatalogRepo, config)
    _ = Supervisor.terminate_child(@app_sup, CatalogRepo)

    case Supervisor.restart_child(@app_sup, CatalogRepo) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
    end
  end

  defp clear_cache! do
    :ets.delete_all_objects(@young_cache)
    :ets.delete_all_objects(@old_cache)
    :ok
  end
end
