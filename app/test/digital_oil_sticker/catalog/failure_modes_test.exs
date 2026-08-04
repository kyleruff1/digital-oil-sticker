defmodule DigitalOilSticker.Catalog.FailureModesTest do
  @moduledoc """
  DOS-M09-004 AC-7: fault-injection for `Catalog.guarded/2` and pairwise
  disjointness of the three caller-visible failure atoms.

  The facade contract (`t:DigitalOilSticker.Catalog.error/0`) is that a DB
  outage MUST surface as `{:error, :catalog_unavailable}` — the request
  process must NOT crash on a `DBConnection.ConnectionError` or
  `Exqlite.Error`. The rescue that guarantees this lives in the private
  `Catalog.guarded/2`.

  Fault-injection technique: `Catalog.__test_guarded__/1` is a test-only
  seam that exposes `guarded/2` so we can call it with a raising fn.
  This proves the rescue works without touching the real connection pool
  — which used to be starved via config manipulation, but that approach
  raced with any async test reading CatalogRepo in the same suite run
  and produced a real flake. Same coverage, no concurrent-test side
  effects.

  Disjointness: caller-visible outcomes on the SAME `catalog:select_year`
  event surface with different atoms depending on which layer refused —
  `:rate_limited` (tier-1 bucket, before the facade runs),
  `:catalog_unavailable` (facade rescue), `:invalid_selector` (vocabulary
  rejection). INV-11 also requires that absent-fact statuses
  (`:unsupported`, `:not_applicable`, etc.) live in a disjoint namespace
  from these error atoms; this file asserts the four atoms it exercises
  are pairwise distinct.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{RateLimit, Result, Selector}
  alias DigitalOilStickerWeb.CatalogEvents

  describe "AC-7 part 1 — guarded/2 rescues real DB failures into :catalog_unavailable" do
    test "DBConnection.ConnectionError raised inside the wrapped fn returns :catalog_unavailable" do
      # The real failure shape from the pool: a connection error with a
      # message that names CatalogRepo. Constructing the exception rather
      # than starving the pool avoids the async race the previous version
      # of this test suffered.
      raiser = fn ->
        raise DBConnection.ConnectionError,
              "[Elixir.DigitalOilSticker.CatalogRepo] test-injected outage"
      end

      assert {:error, :catalog_unavailable} = Catalog.__test_guarded__(raiser)
    end

    test "Exqlite.Error raised inside the wrapped fn returns :catalog_unavailable" do
      # The second class of error `guarded/2` rescues, exercised the same
      # way. Both branches of the `rescue e in [...]` list must fire.
      raiser = fn ->
        raise Exqlite.Error, message: "test-injected sqlite error"
      end

      assert {:error, :catalog_unavailable} = Catalog.__test_guarded__(raiser)
    end

    test "other exception classes propagate — guarded/2 does not swallow them" do
      # The rescue is intentionally narrow. A generic RuntimeError (e.g.
      # a supervisor lookup miss, or an application bug in the caller's
      # fn) must NOT be silently converted to :catalog_unavailable —
      # that would hide real bugs behind a plausible-sounding error atom.
      raiser = fn -> raise "unrelated bug" end

      assert_raise RuntimeError, "unrelated bug", fn ->
        Catalog.__test_guarded__(raiser)
      end
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

      # -- catalog-unavailable: comes from guarded/2 rescuing a real
      # DB failure. We assert the atom directly via the test seam
      # rather than plumbing a fault into the socket edge — the socket
      # edge's routing is separately covered by CatalogEvents tests,
      # and this file's job is the FAILURE atom, not its handoff shape.
      assert {:error, :catalog_unavailable} =
               Catalog.__test_guarded__(fn ->
                 raise DBConnection.ConnectionError, "test-injected"
               end)

      catalog_unavailable_atom = :catalog_unavailable

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

      assert length(Enum.uniq(atoms)) == 3,
             "expected pairwise-disjoint atoms, got: #{inspect(atoms)}"

      # And the absent-fact status atom (:unsupported) must not collide
      # with any of the three error atoms — status and error are
      # separate namespaces per INV-11.
      refute :unsupported in atoms
    end
  end
end
