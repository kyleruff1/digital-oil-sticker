defmodule DigitalOilSticker.Catalog.SubstantiationTest do
  @moduledoc """
  DOS-M09-010 AC-9 — every compatibility or interval claim requires
  source-backed substantiation. Build 1 ships with **zero rows** in the three
  fact tables (`maintenance_schedules`, `oil_requirements`, `filter_fitments`)
  because no licensed authoritative source has been ingested yet (see
  `production.mjs`'s file-header comment; the three-record model of
  DOS-M09-010 FR-7 is not yet built out). This test proves the invariant
  **structurally**: with no source rows, no code path in
  `DigitalOilSticker.Catalog` can synthesize a claim that would map to
  `verified_match` (INV-16, FR-7, RECOMMENDATION_CLAIMS_POLICY).

  The proof works from both ends:

    * **Rows** — direct `CatalogRepo.aggregate/3` counts on the three fact
      tables assert 0 (build 1 ships empty). Read via binary source names
      because no `Ecto.Schema` module exists for these tables in the app
      (see `Catalog.Queries.Service` / `Catalog.Queries.Products` — every
      query uses `from(x in "table_name", ...)`).
    * **Facade** — the two functions that could *ever* upgrade a result off
      `:identity_only` (`get_lubricant_requirements`,
      `list_compatible_filters`) are called for a real fixture
      configuration and asserted to return `:identity_only`. `:identity_only`
      is the honest-no status that carries no interval, no product name, and
      no compatibility claim; `:schedule_supported` and
      `:full_product_supported` both encode "we have source-backed facts",
      either of which would fabricate substantiation. The two upgraded
      statuses are unreachable when the underlying tables are empty.

  For the filter path we mutate `catalog_metadata.feature_filters` to
  `"withheld"` to match build 1's disposition posture — no authorized filter
  source (per FR-1: "the compiler withholds a row when its acquisition
  method, redistribution basis, or resulting claim posture is unresolved").
  Under that flag the `SourceGate` closes and the honest-no qualifier
  `:no_licensed_filter_source` surfaces to the UI layer, which is what a
  future attribution/rendering path (AC-10) will read to explain the empty
  result. This uses the same `:persistent_term`-swap technique as
  `SourceGateTest` and forces `async: false`.
  """
  use ExUnit.Case, async: false
  import Ecto.Query

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{Metadata, Selector}
  alias DigitalOilSticker.CatalogRepo

  @meta_key {Metadata, :metadata}

  setup do
    original = :persistent_term.get(@meta_key)
    on_exit(fn -> :persistent_term.put(@meta_key, original) end)
    {:ok, original: original}
  end

  # Same helper the SourceGateTest uses. `data_version` also rotates so that
  # `Catalog.Cache` (keyed on data_version) does not serve a cached Result
  # from a prior test iteration under the swapped feature flag.
  defp put_features(original, overrides) do
    features = Map.merge(original.features, Map.new(overrides))

    :persistent_term.put(@meta_key, %{
      original
      | features: features,
        data_version: "substantiation-test-#{System.unique_integer([:positive])}"
    })
  end

  defp fetch_identity_config_key do
    CatalogRepo.one(
      from(c in "vehicle_configurations",
        where: c.support_status == "identity_only",
        select: c.configuration_key,
        limit: 1
      )
    )
  end

  describe "AC-9 (rows) — build 1 fact tables carry zero rows" do
    # Zero rows means every downstream `Service.requirements/1`,
    # `Service.schedules/1`, and `Products.fitments_for_configuration/1`
    # returns `[]` for every configuration_key — the input a status
    # upgrade would need is not present in the data.

    test "maintenance_schedules is empty (no licensed schedule source in build 1)" do
      count = CatalogRepo.aggregate(from(t in "maintenance_schedules"), :count, :id)

      assert count == 0,
             "maintenance_schedules must be empty in build 1 — no licensed schedule " <>
               "source has been ingested (got #{count} rows). A non-zero count means a " <>
               "row entered the artifact without a passing DOS-M09-010 disposition."
    end

    test "oil_requirements is empty (no licensed requirement source in build 1)" do
      count = CatalogRepo.aggregate(from(t in "oil_requirements"), :count, :id)

      assert count == 0,
             "oil_requirements must be empty in build 1 — no licensed requirement " <>
               "source has been ingested (got #{count} rows)."
    end

    test "filter_fitments is empty (no licensed filter source in build 1)" do
      count = CatalogRepo.aggregate(from(t in "filter_fitments"), :count, :id)

      assert count == 0,
             "filter_fitments must be empty in build 1 — no licensed filter " <>
               "source has been ingested (got #{count} rows)."
    end
  end

  describe "AC-9 (facade) — no code path can synthesize a claim without source rows" do
    test "get_lubricant_requirements returns :identity_only for a real configuration " <>
           "(never :schedule_supported / :full_product_supported)" do
      key = fetch_identity_config_key()

      assert is_binary(key),
             "fixture must contain an identity_only vehicle_configuration " <>
               "for this test to exercise a real code path"

      {:ok, sel} =
        Selector.validate(:get_lubricant_requirements, %{"configuration_key" => key})

      assert {:ok, %{status: status, data: data}} =
               Catalog.get_lubricant_requirements(sel)

      # Load-bearing check for FR-7: `:schedule_supported` and
      # `:full_product_supported` are the two INV-11 statuses that assert
      # "we have manufacturer-sourced facts for this vehicle". Either would
      # mean a downstream `MatchResult` could reach `verified_match`. With
      # oil_requirements + maintenance_schedules both empty, `Status.derive`
      # short-circuits on the empty-schedules branch and returns
      # `:identity_only` — there is no branch in the whole facade that can
      # reach the two upgraded statuses without at least one source row.
      refute status in [:schedule_supported, :full_product_supported],
             "with zero oil_requirements + zero maintenance_schedules rows, " <>
               "no code path may return #{inspect(status)} — that would fabricate " <>
               "substantiation (INV-16, FR-7)"

      assert status == :identity_only,
             "expected :identity_only, got #{inspect(status)}"

      assert data == [],
             "empty source tables must yield empty data, got #{inspect(data)}"
    end

    test "list_compatible_filters returns :identity_only with data: [] and " <>
           ":no_licensed_filter_source qualifier under build-1 filter disposition",
         %{original: original} do
      # Build 1 has no authorized filter source. The correct disposition
      # for that state is `feature_filters: "withheld"` (per FR-1); under
      # that flag the SourceGate closes and the honest-no qualifier
      # surfaces so a future attribution surface (AC-10) can explain the
      # empty result. The underlying `filter_fitments` table is empty
      # regardless (asserted above), so the substantiation invariant would
      # hold even if the gate were cleared — but the qualifier is what the
      # UI reads to name the reason.
      put_features(original, filters: "withheld")

      key = fetch_identity_config_key()
      assert is_binary(key)

      {:ok, sel} =
        Selector.validate(:list_compatible_filters, %{"configuration_key" => key})

      assert {:ok, %{status: :identity_only, data: [], qualifiers: qualifiers}} =
               Catalog.list_compatible_filters(sel)

      assert Enum.any?(qualifiers, &(&1.code == :no_licensed_filter_source)),
             "closed filters gate must surface :no_licensed_filter_source, got " <>
               inspect(qualifiers)
    end
  end

  describe "AC-9 (enumeration) — every configuration in fixture-a" do
    # Belt-and-suspenders over the single-config check above: sweep EVERY
    # vehicle_configurations row in the fixture across all three facades
    # whose branches include the two upgraded statuses. If a future ingest
    # ever produces a row that reaches an upgraded branch — a config whose
    # completeness/support_status columns disagree with the fact tables,
    # or a Status.derive path change that bypasses the empty-schedule
    # short-circuit — this sweep pins the offending (facade, key, status)
    # tuple rather than surfacing as one flake on one arbitrary row.
    #
    # The three facades enumerated are the only ones that consume fact
    # tables (`Service.schedules`, `Service.requirements`,
    # `Products.fitments_for_configuration`); the identity facades
    # (list_years / list_makes / list_models / list_configurations) always
    # return `:identity_only` structurally, and the oil-model facades
    # return the separate `:our_model` status which is out of scope for
    # INV-11 fact substantiation.
    test "no config reaches :schedule_supported / :full_product_supported " <>
           "across the three fact-yielding facades" do
      keys =
        CatalogRepo.all(from(c in "vehicle_configurations", select: c.configuration_key))

      assert length(keys) > 0,
             "fixture must contain vehicle_configurations rows for this sweep " <>
               "to exercise anything (got 0)"

      facades = [
        {:get_schedules, &Catalog.get_schedules/1},
        {:get_lubricant_requirements, &Catalog.get_lubricant_requirements/1},
        {:list_compatible_filters, &Catalog.list_compatible_filters/1}
      ]

      forbidden = [:schedule_supported, :full_product_supported]

      offenders =
        Enum.flat_map(keys, fn key ->
          Enum.flat_map(facades, fn {name, fun} ->
            # Deliberate hard-match: every configuration_key in the fixture
            # is a UUID that satisfies Selector's id regex, so validate/2
            # must succeed and the facade must return {:ok, _}. A future
            # regression that violates either invariant crashes with a
            # MatchError naming the offending (name, key), which is more
            # actionable than a filtered-out silent skip.
            {:ok, sel} = Selector.validate(name, %{"configuration_key" => key})
            {:ok, %{status: status}} = fun.(sel)
            if status in forbidden, do: [{name, key, status}], else: []
          end)
        end)

      assert offenders == [],
             "AC-9 invariant broken: with zero rows in maintenance_schedules, " <>
               "oil_requirements, and filter_fitments, no facade call may return " <>
               ":schedule_supported / :full_product_supported for any of the " <>
               "#{length(keys)} configurations in fixture-a. First 10 offenders: " <>
               inspect(Enum.take(offenders, 10))
    end

    test "every config resolves to the honest-empty set " <>
           "(:identity_only / :not_applicable / :unsupported)" do
      # Complement to the previous test — instead of just refuting the two
      # upgraded statuses, positively enumerate what IS allowed. Any status
      # outside `allowed` (e.g. `:our_model` leaking, an atom typo, a new
      # status added by a refactor) trips this before it can be interpreted
      # by callers that pattern-match on the old set.
      keys =
        CatalogRepo.all(from(c in "vehicle_configurations", select: c.configuration_key))

      facades = [
        {:get_schedules, &Catalog.get_schedules/1},
        {:get_lubricant_requirements, &Catalog.get_lubricant_requirements/1},
        {:list_compatible_filters, &Catalog.list_compatible_filters/1}
      ]

      allowed = [:identity_only, :not_applicable, :unsupported]

      offenders =
        Enum.flat_map(keys, fn key ->
          Enum.flat_map(facades, fn {name, fun} ->
            {:ok, sel} = Selector.validate(name, %{"configuration_key" => key})
            {:ok, %{status: status}} = fun.(sel)
            if status in allowed, do: [], else: [{name, key, status}]
          end)
        end)

      assert offenders == [],
             "every facade call over fixture-a must resolve to one of " <>
               "#{inspect(allowed)}; got out-of-set statuses: " <>
               inspect(Enum.take(offenders, 10))
    end
  end

  describe "AC-9 (structural) — persisted enum excludes :verified_match" do
    # The :verified_match token belongs to the FR-7 MatchResult record kind
    # (not built in build 1) and MUST NOT leak into a persisted `condition`
    # value on maintenance_schedules — not via a stray raw-SQL INSERT, not
    # via a future migration that widens the CHECK enum, not via a table
    # recreate that drops the CHECK entirely. The two tests below pin both
    # ends: no row currently carries the value, and the DDL itself does not
    # permit it.

    test "no maintenance_schedules row has condition='verified_match'" do
      count =
        CatalogRepo.aggregate(
          from(m in "maintenance_schedules", where: m.condition == "verified_match"),
          :count,
          :id
        )

      assert count == 0,
             "no maintenance_schedules row may have condition='verified_match' " <>
               "(got #{count}). The CHECK constraint should reject the value " <>
               "on INSERT; this guard fires if a future migration widens the " <>
               "enum or a raw-SQL path bypasses it."
    end

    test "maintenance_schedules.condition CHECK does not permit 'verified_match'" do
      # Read the DDL directly from sqlite_master. If a future migration
      # widens the allowed enum to include 'verified_match', or someone
      # recreates the table without the CHECK, this refute trips before
      # any offending row can be inserted.
      %{rows: [[ddl]]} =
        Ecto.Adapters.SQL.query!(
          CatalogRepo,
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'maintenance_schedules'",
          []
        )

      assert is_binary(ddl),
             "sqlite_master must expose the maintenance_schedules DDL as a string"

      refute String.contains?(ddl, "verified_match"),
             "maintenance_schedules DDL must not mention 'verified_match'. " <>
               "The condition CHECK is the last line of defense against a " <>
               "MatchResult token leaking into a persisted schedule row."

      # DDL-shape sanity check: if the CHECK clause ever moves or the
      # legitimate values are renamed, the refute above becomes vacuous.
      # Assert the three real values are present so the guard stays honest.
      for value <- ["'normal'", "'severe'", "'flexible'"] do
        assert String.contains?(ddl, value),
               "DDL sanity check: expected #{value} inside the condition CHECK " <>
                 "of maintenance_schedules; got:\n#{ddl}"
      end
    end
  end

  describe "AC-9 (absence guard) — no MatchResult module in lib/ yet" do
    # FR-7 defines a MatchResult record kind that a future ingest layer
    # (M03+) will emit. In build 1 it must not exist: no code path can
    # construct a `:verified_match` if there is no code that emits the
    # token. This test pins that absence — if a future PR introduces a
    # MatchResult module (or a bare `match_result` reference) into `lib/`
    # without first widening this suite to assert the new module cannot
    # produce `:verified_match` under the current source-gate state, CI
    # turns red and the author has to consciously extend AC-9 coverage in
    # the same change instead of silently expanding the substantiation
    # surface.
    test "lib/ has no MatchResult / match_result reference" do
      lib_root = Path.expand(Path.join(__DIR__, "../../../lib"))

      assert File.dir?(lib_root),
             "lib/ must exist at #{lib_root} for this scan to be meaningful"

      ex_files = Path.wildcard(Path.join(lib_root, "**/*.{ex,exs}"))

      assert length(ex_files) > 0,
             "at least one .ex/.exs file must exist under lib/ for the scan to " <>
               "be meaningful"

      # `\b` word-boundary avoids false positives on substrings like
      # `mismatch_result` or `unmatched_result_row`. Case-sensitive: catches
      # `MatchResult` (module), `match_result` (function/atom/field), but not
      # unrelated tokens that happen to share a prefix.
      pattern = ~r/\b(MatchResult|match_result)\b/

      offenders =
        Enum.filter(ex_files, fn file ->
          Regex.match?(pattern, File.read!(file))
        end)

      assert offenders == [],
             "no MatchResult / match_result reference may exist in lib/ until " <>
               "FR-7's ingest layer lands. If you are introducing it, extend " <>
               "AC-9's substantiation suite in the SAME change to assert the " <>
               "new module cannot produce :verified_match given the current " <>
               "source-gate state. Offending files: #{inspect(offenders)}"
    end
  end
end
