defmodule DigitalOilSticker.Catalog.SourceGateTest do
  @moduledoc """
  AC-15: A source-gate "no" is a legitimate INV-11 status return, not an
  error. The runtime source for each fact-domain flag is
  `Catalog.Metadata.feature/1`, backed by `:persistent_term` loaded once at
  boot from `catalog_metadata`; there is no injectable seam and no mock
  library in the deps. This module therefore drives the flip by rewriting
  the persistent-term entry with synthetic feature values, exercises
  `SourceGate` directly and every facade function that consults it —

    * `Catalog.list_compatible_filters/1` via `:filters`
    * `Catalog.get_schedules/1` via `:maintenance_schedules`
      (checked inside `Status.derive/2`)
    * `Catalog.get_lubricant_requirements/1` via `:oil_requirements`
    * `Catalog.search_oils/1` via `:oil_products`

  — and restores the original entry in an `on_exit` hook.

  `async: false` is required — `:persistent_term` is process-global, so any
  test running concurrently that read `Metadata.feature/1` would race the
  swap. The Catalog `Cache` keys on `Metadata.data_version/0` (not on the
  feature flags), so each swap also rotates `data_version` to force a cache
  miss — otherwise the second test's flag change would be masked by the
  first test's cached `Result`.
  """
  use ExUnit.Case, async: false

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{Metadata, Selector, SourceGate}
  import Ecto.Query

  @meta_key {Metadata, :metadata}

  setup do
    original = :persistent_term.get(@meta_key)
    on_exit(fn -> :persistent_term.put(@meta_key, original) end)
    {:ok, original: original}
  end

  # Rotates the persistent-term metadata so `SourceGate` sees `overrides` and
  # `Cache` sees a fresh `data_version` (its key includes data_version but
  # never the feature flags — without the rotation, two tests using the same
  # selector would collide on the cached Result from the first).
  defp put_features(original, overrides) do
    features = Map.merge(original.features, Map.new(overrides))

    :persistent_term.put(@meta_key, %{
      original
      | features: features,
        data_version: "sourcegate-test-#{System.unique_integer([:positive])}"
    })
  end

  defp fetch_identity_config_key do
    DigitalOilSticker.CatalogRepo.one(
      from(c in "vehicle_configurations",
        where: c.support_status == "identity_only",
        select: c.configuration_key,
        limit: 1
      )
    )
  end

  describe "SourceGate.cleared?/1 flag mapping (direct unit)" do
    test "filters: only 'withheld' blocks; 'absent' and 'present' clear", %{original: original} do
      for {value, expected} <- [{"withheld", false}, {"absent", true}, {"present", true}] do
        put_features(original, filters: value)

        assert SourceGate.cleared?(:filters) == expected,
               "SourceGate.cleared?(:filters) with feature=#{inspect(value)} " <>
                 "should be #{expected}"
      end
    end

    test "maintenance_schedules: only 'withheld' blocks; 'absent' and 'present' clear",
         %{original: original} do
      for {value, expected} <- [{"withheld", false}, {"absent", true}, {"present", true}] do
        put_features(original, schedules: value)
        assert SourceGate.cleared?(:maintenance_schedules) == expected
      end
    end

    test "oil_products: 'withheld' AND 'absent' both block; only 'present' clears",
         %{original: original} do
      # oil_products is the one gate that treats "absent" as a serving no —
      # a source with unresolved acquisition/redistribution/claim posture
      # contributes zero rows at build time, so its runtime absence and its
      # withheld posture are indistinguishable from the client's side.
      for {value, expected} <- [{"withheld", false}, {"absent", false}, {"present", true}] do
        put_features(original, oil_products: value)
        assert SourceGate.cleared?(:oil_products) == expected
      end
    end

    test "oil_requirements: only 'withheld' blocks; 'absent' and 'present' clear",
         %{original: original} do
      for {value, expected} <- [{"withheld", false}, {"absent", true}, {"present", true}] do
        put_features(original, oil_requirements: value)
        assert SourceGate.cleared?(:oil_requirements) == expected
      end
    end
  end

  describe "list_compatible_filters flips on the :filters flag (facade integration)" do
    setup do
      key = fetch_identity_config_key()
      assert is_binary(key), "fixture must contain an identity_only vehicle_configuration"
      {:ok, key: key}
    end

    test "'withheld' returns :identity_only + :no_licensed_filter_source, NOT {:error, ...}",
         %{original: original, key: key} do
      put_features(original, filters: "withheld")

      {:ok, sel} = Selector.validate(:list_compatible_filters, %{"configuration_key" => key})

      assert {:ok, %{status: :identity_only, data: [], qualifiers: qualifiers}} =
               Catalog.list_compatible_filters(sel)

      assert Enum.any?(qualifiers, &(&1.code == :no_licensed_filter_source)),
             "withheld filters must surface the :no_licensed_filter_source qualifier"
    end

    test "'absent' clears the gate — no :no_licensed_filter_source qualifier, no error",
         %{original: original, key: key} do
      put_features(original, filters: "absent")

      {:ok, sel} = Selector.validate(:list_compatible_filters, %{"configuration_key" => key})

      assert {:ok, %{status: status, qualifiers: qualifiers}} =
               Catalog.list_compatible_filters(sel)

      # Gate cleared → Products lookup runs. The fixture holds no filter
      # rows, so :identity_only is the honest empty answer; what matters
      # for AC-15 is that we did NOT short-circuit on the gate.
      assert status in [:identity_only, :full_product_supported]

      refute Enum.any?(qualifiers, &(&1.code == :no_licensed_filter_source)),
             "gate-cleared result must not carry the gate-blocked qualifier"
    end

    test "'present' clears the gate — no :no_licensed_filter_source qualifier, no error",
         %{original: original, key: key} do
      put_features(original, filters: "present")

      {:ok, sel} = Selector.validate(:list_compatible_filters, %{"configuration_key" => key})

      assert {:ok, %{status: status, qualifiers: qualifiers}} =
               Catalog.list_compatible_filters(sel)

      assert status in [:identity_only, :full_product_supported]

      refute Enum.any?(qualifiers, &(&1.code == :no_licensed_filter_source))
    end
  end

  describe "get_schedules flips on the :schedules flag (facade integration)" do
    setup do
      key = fetch_identity_config_key()
      assert is_binary(key)
      {:ok, key: key}
    end

    test "'withheld' returns :unsupported + :source_not_cleared_for_web_serving, NOT {:error, ...}",
         %{original: original, key: key} do
      put_features(original, schedules: "withheld")

      {:ok, sel} = Selector.validate(:get_schedules, %{"configuration_key" => key})

      assert {:ok, %{status: :unsupported, data: [], qualifiers: qualifiers}} =
               Catalog.get_schedules(sel)

      assert Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :maintenance_schedules)
             )
    end

    test "'absent' clears the gate — status derives normally (no gate-blocked qualifier)",
         %{original: original, key: key} do
      put_features(original, schedules: "absent")

      {:ok, sel} = Selector.validate(:get_schedules, %{"configuration_key" => key})
      assert {:ok, %{status: status, qualifiers: qualifiers}} = Catalog.get_schedules(sel)

      # Gate cleared → identity-only config with no fixture schedule rows
      # collapses to :identity_only via `outcome.schedules == []`, not via
      # the gate.
      assert status == :identity_only

      refute Enum.any?(qualifiers, &(&1.code == :source_not_cleared_for_web_serving))
    end

    test "'present' clears the gate — status derives normally (no gate-blocked qualifier)",
         %{original: original, key: key} do
      put_features(original, schedules: "present")

      {:ok, sel} = Selector.validate(:get_schedules, %{"configuration_key" => key})
      assert {:ok, %{status: status, qualifiers: qualifiers}} = Catalog.get_schedules(sel)

      assert status == :identity_only
      refute Enum.any?(qualifiers, &(&1.code == :source_not_cleared_for_web_serving))
    end
  end

  describe "get_lubricant_requirements flips on the :oil_requirements flag (facade integration)" do
    setup do
      key = fetch_identity_config_key()
      assert is_binary(key), "fixture must contain an identity_only vehicle_configuration"
      {:ok, key: key}
    end

    test "'withheld' returns :identity_only + :source_not_cleared_for_web_serving on :oil_requirements",
         %{original: original, key: key} do
      put_features(original, oil_requirements: "withheld")

      {:ok, sel} =
        Selector.validate(:get_lubricant_requirements, %{"configuration_key" => key})

      assert {:ok, %{status: :identity_only, data: [], qualifiers: qualifiers}} =
               Catalog.get_lubricant_requirements(sel)

      assert Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :oil_requirements)
             ),
             "withheld oil_requirements must surface the gate-blocked qualifier " <>
               "with fact_domain :oil_requirements"
    end

    test "'absent' clears the :oil_requirements gate — no gate-blocked qualifier, no error",
         %{original: original, key: key} do
      put_features(original, oil_requirements: "absent")

      {:ok, sel} =
        Selector.validate(:get_lubricant_requirements, %{"configuration_key" => key})

      assert {:ok, %{status: status, qualifiers: qualifiers}} =
               Catalog.get_lubricant_requirements(sel)

      # Gate cleared → Service.requirements runs. Fixture is identity-only
      # with zero requirement rows, so honest empty answer is :identity_only.
      assert status == :identity_only

      refute Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :oil_requirements)
             ),
             "gate-cleared result must not carry the :oil_requirements gate-blocked qualifier"
    end

    test "'present' clears the :oil_requirements gate — no gate-blocked qualifier, no error",
         %{original: original, key: key} do
      put_features(original, oil_requirements: "present")

      {:ok, sel} =
        Selector.validate(:get_lubricant_requirements, %{"configuration_key" => key})

      assert {:ok, %{status: status, qualifiers: qualifiers}} =
               Catalog.get_lubricant_requirements(sel)

      assert status == :identity_only

      refute Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :oil_requirements)
             )
    end

    test "gate check precedes configuration lookup — but is_nil(config) still short-circuits first",
         %{original: original} do
      # `get_lubricant_requirements` short-circuits `nil` config to :unsupported
      # BEFORE consulting the gate, so a bogus configuration_key under a
      # withheld gate still surfaces the config-not-in-data-version qualifier
      # rather than the gate qualifier. Verifying that ordering keeps future
      # refactors from flipping it (which would leak the existence of a
      # configuration by returning gate-blocked instead of unsupported).
      put_features(original, oil_requirements: "withheld")

      {:ok, sel} =
        Selector.validate(:get_lubricant_requirements, %{
          "configuration_key" => "not-a-real-key-999"
        })

      assert {:ok, %{status: :unsupported, qualifiers: qualifiers}} =
               Catalog.get_lubricant_requirements(sel)

      assert Enum.any?(qualifiers, &(&1.code == :configuration_not_in_data_version))
    end
  end

  describe "search_oils flips on the :oil_products flag (facade integration)" do
    # search_oils takes a `requirement_id`, not a `configuration_key`. Any
    # selector-valid id serves the gate-blocked branch (the gate short-
    # circuits before the DB check); the cleared-gate branch falls through
    # to `Products.requirement_exists?/1` which returns false against the
    # empty `oil_requirements` fixture.
    @fake_requirement_id "req-does-not-exist-1"

    test "'withheld' returns :identity_only + :source_not_cleared_for_web_serving on :oil_products",
         %{original: original} do
      put_features(original, oil_products: "withheld")

      {:ok, sel} =
        Selector.validate(:search_oils, %{"requirement_id" => @fake_requirement_id})

      assert {:ok, %{status: :identity_only, data: [], qualifiers: qualifiers}} =
               Catalog.search_oils(sel)

      assert Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :oil_products)
             ),
             "withheld oil_products must surface the gate-blocked qualifier " <>
               "with fact_domain :oil_products"
    end

    test "'absent' ALSO blocks — oil_products treats absent as a serving no",
         %{original: original} do
      # The one gate that fails closed on "absent" (see SourceGate.cleared?/1
      # for :oil_products). If the runtime posture ever softens this to only
      # block "withheld" it would silently start listing products under a
      # source with unresolved acquisition/redistribution/claim posture.
      put_features(original, oil_products: "absent")

      {:ok, sel} =
        Selector.validate(:search_oils, %{"requirement_id" => @fake_requirement_id})

      assert {:ok, %{status: :identity_only, data: [], qualifiers: qualifiers}} =
               Catalog.search_oils(sel)

      assert Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :oil_products)
             )
    end

    test "'present' clears the :oil_products gate — falls through to the requirement check",
         %{original: original} do
      put_features(original, oil_products: "present")

      {:ok, sel} =
        Selector.validate(:search_oils, %{"requirement_id" => @fake_requirement_id})

      assert {:ok, %{status: status, qualifiers: qualifiers}} = Catalog.search_oils(sel)

      # Gate cleared → Products.requirement_exists?/1 runs. Fixture has no
      # `oil_requirements` rows, so the fake id is honestly unresolved and
      # collapses to :unsupported. What matters for AC-15 is that the gate
      # qualifier is absent — the downstream branch owns the outcome.
      assert status == :unsupported

      refute Enum.any?(
               qualifiers,
               &(&1.code == :source_not_cleared_for_web_serving and
                   &1.fact_domain == :oil_products)
             ),
             "gate-cleared result must not carry the :oil_products gate-blocked qualifier"
    end
  end

  describe "no source-gate flip ever surfaces as {:error, ...}" do
    test "every combination of flag values on all four gated facades stays inside {:ok, _}",
         %{original: original} do
      key = fetch_identity_config_key()
      assert is_binary(key)

      values = ["absent", "withheld", "present"]

      {:ok, filters_sel} =
        Selector.validate(:list_compatible_filters, %{"configuration_key" => key})

      {:ok, schedules_sel} = Selector.validate(:get_schedules, %{"configuration_key" => key})

      {:ok, requirements_sel} =
        Selector.validate(:get_lubricant_requirements, %{"configuration_key" => key})

      {:ok, oils_sel} =
        Selector.validate(:search_oils, %{"requirement_id" => "req-matrix-probe-1"})

      for schedules <- values,
          filters <- values,
          oil_products <- values,
          oil_requirements <- values do
        put_features(original,
          schedules: schedules,
          filters: filters,
          oil_products: oil_products,
          oil_requirements: oil_requirements
        )

        combo =
          "schedules=#{schedules} filters=#{filters} " <>
            "oil_products=#{oil_products} oil_requirements=#{oil_requirements}"

        assert match?({:ok, _}, Catalog.list_compatible_filters(filters_sel)),
               "list_compatible_filters returned {:error, ...} under " <> combo

        assert match?({:ok, _}, Catalog.get_schedules(schedules_sel)),
               "get_schedules returned {:error, ...} under " <> combo

        assert match?({:ok, _}, Catalog.get_lubricant_requirements(requirements_sel)),
               "get_lubricant_requirements returned {:error, ...} under " <> combo

        assert match?({:ok, _}, Catalog.search_oils(oils_sel)),
               "search_oils returned {:error, ...} under " <> combo
      end
    end
  end
end
