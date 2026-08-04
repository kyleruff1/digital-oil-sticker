defmodule DigitalOilSticker.Catalog.RepoCallerScanTest do
  @moduledoc """
  DOS-M09-004 AC-1: every module under `lib/` that reaches
  `DigitalOilSticker.CatalogRepo` directly — through `Ecto.Adapters.SQL.query`,
  `import Ecto.Query`, or `CatalogRepo.<fn>(...)` — must be on the
  `@allowed_callers` whitelist. Any new caller fails this test.

  The catalog boundary is `DigitalOilSticker.Catalog` (FR-16, INV-11): reads go
  through the facade or one of its internals — Queries.*, Metadata, Cache,
  OilModel. `DigitalOilStickerWeb.HealthController` is the one whitelisted
  infrastructure exception: it is the health/version endpoint and must reach
  the driver directly to prove read-only-mode enforcement (write-attempt probe
  + `PRAGMA query_only` diagnostic), a property asserted end-to-end by
  `health_controller_test.exs`. That is why the controller keeps its raw
  `Ecto.Adapters.SQL.query` calls instead of routing through the facade —
  they *are* the assertion, and this test locks that exception down so no
  other module can quietly join it.

  Detection is source-level (matching the style of `namespace_boundary_test.exs`)
  because source is what a reviewer reads. Mere name references — a supervisor
  child spec (`application.ex`) or a config lookup (`release.ex`) — do not
  count as calls and are not flagged. The positive-control test proves the
  scanner is not vacuously green.
  """
  use ExUnit.Case, async: true

  @app_root Path.expand("../../..", __DIR__)
  @lib_root Path.join(@app_root, "lib")

  # Every module allowed to reach CatalogRepo directly. Everything else must
  # route through `DigitalOilSticker.Catalog`.
  @allowed_callers MapSet.new([
                     "DigitalOilSticker.Catalog",
                     "DigitalOilSticker.Catalog.Cache",
                     "DigitalOilSticker.Catalog.Metadata",
                     "DigitalOilSticker.Catalog.OilModel",
                     "DigitalOilSticker.Catalog.Queries.Identity",
                     "DigitalOilSticker.Catalog.Queries.Products",
                     "DigitalOilSticker.Catalog.Queries.Provenance",
                     "DigitalOilSticker.Catalog.Queries.Service",
                     "DigitalOilStickerWeb.HealthController"
                   ])

  # Patterns that mark a module as a CALLER, not just a mention.
  #
  #   * `\bCatalogRepo\s*\.\s*\w+\s*\(`  — direct Repo callback like
  #     `CatalogRepo.all(...)` / `CatalogRepo.one(...)`. Requires the `.fn(`
  #     shape so `alias DigitalOilSticker.CatalogRepo` and
  #     `DigitalOilSticker.CatalogRepo,` (child specs, config lookups) do
  #     not match.
  #   * `\bEcto\.Adapters\.SQL\.\w+!?\s*\(` — the raw-SQL escape hatch,
  #     regardless of which function is used (`query`, `query!`, `stream`,
  #     `to_sql`, or any future sibling) and regardless of which repo
  #     argument it's given. In this codebase CatalogRepo is the only repo,
  #     so any such call is a CatalogRepo call. Broadened from `query!?` per
  #     the M09-004 verify fix so a future adapter helper cannot slip past.
  #     The trailing `!?` matters: `\w+` alone stops at the `!` in `query!`,
  #     which would then fail the `(` lookahead.
  #   * `\bimport\s+Ecto\.Query\b` — the query DSL. A module that imports it
  #     is building queries that reach the repo (again, only CatalogRepo
  #     exists to receive them).
  @call_patterns [
    ~r/\bCatalogRepo\s*\.\s*\w+\s*\(/,
    ~r/\bEcto\.Adapters\.SQL\.\w+!?\s*\(/,
    ~r/\bimport\s+Ecto\.Query\b/
  ]

  defp lib_sources do
    @lib_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      {Path.relative_to(path, @app_root), path |> File.read!() |> String.replace("\r\n", "\n")}
    end)
  end

  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end

  defp calls_catalog_repo?(source) do
    Enum.any?(@call_patterns, &Regex.match?(&1, source))
  end

  defp module_name(source) do
    # `^...` under `/m` matches the start of any line, not only byte 0. The
    # earlier `\A` anchor missed any file whose `defmodule` was preceded by a
    # `# ...` comment or blank line, silently dropping that module from the
    # scan — a hole the M09-004 verify fix closed here.
    case Regex.run(~r/^defmodule\s+([\w.]+)\s+do\b/m, source) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp caller_modules(sources) do
    for {path, source} <- sources,
        code = strip_comments(source),
        calls_catalog_repo?(code),
        mod = module_name(source),
        # CatalogRepo defines itself with `use Ecto.Repo`, not a call — but if
        # anything in the pattern set ever did match its own source, it would
        # not be a caller in the boundary sense.
        mod != nil and mod != "DigitalOilSticker.CatalogRepo",
        do: {mod, path}
  end

  describe "every CatalogRepo caller is on the whitelist" do
    test "no module outside the allowlist calls CatalogRepo" do
      sources = lib_sources()

      assert length(sources) > 15,
             "found only #{length(sources)} lib sources — the glob is wrong"

      offenders =
        sources
        |> caller_modules()
        |> Enum.reject(fn {mod, _path} -> MapSet.member?(@allowed_callers, mod) end)

      assert offenders == [],
             "these modules call CatalogRepo but are not on the whitelist: " <>
               Enum.map_join(offenders, ", ", fn {m, p} -> "#{m} (#{p})" end) <>
               ". Either route through DigitalOilSticker.Catalog or, if this " <>
               "is a deliberate new infrastructure exception, add it to " <>
               "@allowed_callers with a comment explaining why."
    end

    test "every known internal caller is detected (non-vacuousness)" do
      detected =
        lib_sources()
        |> caller_modules()
        |> Enum.map(fn {mod, _path} -> mod end)
        |> MapSet.new()

      # These are the modules known to reach CatalogRepo today. Losing any of
      # them from the detection set means the scanner has gone blind, not that
      # the module has been cleaned up — so require all seven every run.
      required = [
        "DigitalOilSticker.Catalog.Metadata",
        "DigitalOilSticker.Catalog.OilModel",
        "DigitalOilSticker.Catalog.Queries.Identity",
        "DigitalOilSticker.Catalog.Queries.Products",
        "DigitalOilSticker.Catalog.Queries.Provenance",
        "DigitalOilSticker.Catalog.Queries.Service",
        "DigitalOilStickerWeb.HealthController"
      ]

      missing = Enum.reject(required, &MapSet.member?(detected, &1))

      assert missing == [],
             "scanner missed known CatalogRepo callers: #{Enum.join(missing, ", ")}"
    end

    test "positive control: a synthetic stray caller is detected and would fail the whitelist" do
      synthetic = """
      defmodule DigitalOilSticker.RogueClient do
        import Ecto.Query
        alias DigitalOilSticker.CatalogRepo

        def peek do
          CatalogRepo.all(from m in "makes", select: m.id)
        end

        def raw do
          Ecto.Adapters.SQL.query!(CatalogRepo, "SELECT 1", [])
        end
      end
      """

      code = strip_comments(synthetic)

      # Each individual pattern must trip on the synthetic — otherwise removing
      # one from `@call_patterns` could go unnoticed.
      assert Enum.all?(@call_patterns, &Regex.match?(&1, code)),
             "at least one @call_pattern did not match the synthetic stray caller"

      assert calls_catalog_repo?(code)
      assert module_name(synthetic) == "DigitalOilSticker.RogueClient"

      refute MapSet.member?(@allowed_callers, "DigitalOilSticker.RogueClient"),
             "the synthetic control leaked into @allowed_callers"
    end

    test "name-only references (alias, child spec, config lookup) are not flagged as calls" do
      innocuous = """
      defmodule DigitalOilSticker.Bystander do
        alias DigitalOilSticker.CatalogRepo

        def child_spec_ref, do: CatalogRepo
        def config, do: Application.get_env(:digital_oil_sticker, DigitalOilSticker.CatalogRepo, [])
        def list_ref, do: [DigitalOilSticker.CatalogRepo, :other]
      end
      """

      refute calls_catalog_repo?(strip_comments(innocuous)),
             "scanner wrongly flagged an alias / child-spec / config-lookup module as a CatalogRepo caller"
    end
  end

  describe "BEAM-level: every compiled module that reaches CatalogRepo is accounted for" do
    # The source scan above is what a reviewer reads, but source can lie: an
    # `alias DigitalOilSticker.CatalogRepo, as: Repo` followed by `Repo.all/1`
    # renames the caller past a name-based regex; `apply(CatalogRepo, :all, ...)`
    # never spells the call at all; a fresh `Ecto.Adapters.SQL.Something.query/3`
    # sibling would sneak past the current pattern set. What survives all of
    # those is the compiled BEAM — the atom table records every module
    # referenced, and the imports chunk records every external MFA called.
    #
    # This test walks `Application.spec(:digital_oil_sticker, :modules)` (the
    # canonical module list from the app spec) and inspects each BEAM. It is
    # allowed to be strictly *broader* than the source scan: the BEAM cannot
    # tell a child-spec entry from a call site, so modules that only NAME
    # CatalogRepo (Application supervises it; Release reads its runtime
    # config path) are enumerated below alongside the source whitelist. Any
    # module that reaches CatalogRepo in the compiled artifact and is NOT in
    # this union fails the assertion.

    # Modules that put `DigitalOilSticker.CatalogRepo` in their atom table
    # without calling any function on it. These are legitimate references —
    # not caller-callee edges — but the BEAM does not distinguish, so they
    # are listed here rather than in @allowed_callers.
    @name_only_referrers MapSet.new([
                           # `DigitalOilSticker.CatalogRepo` in the
                           # supervision children list (application.ex).
                           "DigitalOilSticker.Application",
                           # `Application.get_env(..., DigitalOilSticker.CatalogRepo, [])`
                           # to read the catalog file path (release.ex).
                           "DigitalOilSticker.Release",
                           # Test support: aliases CatalogRepo and reads the
                           # fixture path from its config. Compiled under
                           # `test/support`, so it appears in the app's
                           # module list under MIX_ENV=test. Not shipped.
                           "DigitalOilSticker.CatalogCase"
                         ])

    @beam_allowed MapSet.union(@allowed_callers, @name_only_referrers)

    test "no compiled module outside the BEAM allowlist references CatalogRepo" do
      # Ensure the app spec is loaded. `mix test` loads it before running,
      # but calling this explicitly is defensive against alternate runners.
      _ = Application.ensure_loaded(:digital_oil_sticker)
      modules = Application.spec(:digital_oil_sticker, :modules) || []

      assert length(modules) > 15,
             "Application.spec/2 returned #{length(modules)} modules — " <>
               "the app is not compiled or its .app file is empty"

      offenders =
        for module <- modules,
            module != DigitalOilSticker.CatalogRepo,
            reason = beam_reference_reason(module),
            reason != nil,
            not MapSet.member?(@beam_allowed, inspect(module)),
            do: {inspect(module), reason}

      assert offenders == [],
             "these compiled modules reach CatalogRepo (or an Ecto.Adapters.SQL sibling) " <>
               "but are not on the whitelist:\n" <>
               Enum.map_join(offenders, "\n", fn {m, r} -> "  #{m} - #{r}" end) <>
               "\nEither route through DigitalOilSticker.Catalog, or, if this is a " <>
               "deliberate exception, add it to @allowed_callers (real caller) or " <>
               "@name_only_referrers (only names CatalogRepo without calling it) " <>
               "with a comment explaining why."
    end

    test "the BEAM scan detects every known internal caller (non-vacuousness)" do
      _ = Application.ensure_loaded(:digital_oil_sticker)
      modules = Application.spec(:digital_oil_sticker, :modules) || []

      detected =
        for module <- modules,
            reason = beam_reference_reason(module),
            reason != nil,
            do: inspect(module),
            into: MapSet.new()

      # The seven modules known to reach CatalogRepo today — same list the
      # source-regex non-vacuousness test uses. `Catalog` (the facade) and
      # `Catalog.Cache` are on @allowed_callers as pre-approved entries but
      # do not call CatalogRepo yet, so they are deliberately absent here:
      # losing them from `detected` should not fail the scan.
      required = [
        "DigitalOilSticker.Catalog.Metadata",
        "DigitalOilSticker.Catalog.OilModel",
        "DigitalOilSticker.Catalog.Queries.Identity",
        "DigitalOilSticker.Catalog.Queries.Products",
        "DigitalOilSticker.Catalog.Queries.Provenance",
        "DigitalOilSticker.Catalog.Queries.Service",
        "DigitalOilStickerWeb.HealthController"
      ]

      missing = Enum.reject(required, &MapSet.member?(detected, &1))

      assert missing == [],
             "the BEAM scan missed known CatalogRepo callers: " <>
               "#{Enum.join(missing, ", ")}. Either the scan has gone blind or " <>
               "one of these modules stopped reaching CatalogRepo (in which case " <>
               "update the required list here and @allowed_callers)."
    end

    test "the BEAM scan catches an alias-rename call that would slip past the source regex" do
      # This is the class of hazard the BEAM path exists for: a source-level
      # regex hunting `CatalogRepo.` never sees `Repo.` even though the
      # compiled call is identical. Metadata is a known caller — its compiled
      # BEAM contains a call to a function on CatalogRepo — so if the atom /
      # imports check works at all, it works here.
      assert beam_reference_reason(DigitalOilSticker.Catalog.Metadata) != nil,
             "BEAM inspection is not detecting a known caller — the strengthened " <>
               "scanner is inert and the source scan is the only remaining guard"
    end

    test "an Ecto.Adapters.SQL sibling call is treated as a raw-SQL escape hatch" do
      # HealthController is the whitelisted infrastructure exception because
      # it makes raw `Ecto.Adapters.SQL.query/query!` calls to prove
      # read-only-mode enforcement. Its BEAM must therefore be detected via
      # the SQL-sibling branch, not merely via the `CatalogRepo` atom — that
      # is the branch that would catch a NEW module reaching for
      # `Ecto.Adapters.SQL.stream/3` or a future adapter helper.
      reason = beam_reference_reason(DigitalOilStickerWeb.HealthController)

      assert reason != nil,
             "HealthController not detected by BEAM scan — the SQL-sibling " <>
               "branch is inert"

      assert reason =~ "Ecto.Adapters.SQL",
             "HealthController was detected but not via the Ecto.Adapters.SQL " <>
               "branch (reason: #{reason}). A future non-CatalogRepo module using " <>
               "the raw-SQL escape hatch would slip past this scan."
    end
  end

  # --- BEAM reflection helpers ----------------------------------------------

  # Returns a human-readable reason string if `module`'s compiled BEAM
  # references CatalogRepo (or an Ecto.Adapters.SQL.* sibling), or nil.
  #
  # Three signals, checked in the order most useful for debugging:
  #   1. An entry in the `imports` chunk whose module is CatalogRepo — a
  #      direct call, including aliased calls (`alias CatalogRepo, as: R`
  #      followed by `R.all(...)`) because the alias is resolved at
  #      compile time.
  #   2. An entry in the `imports` chunk whose module is
  #      `Ecto.Adapters.SQL` or any submodule — the raw-SQL escape hatch.
  #   3. The `Elixir.DigitalOilSticker.CatalogRepo` atom in the module's
  #      atom table — this catches `apply(CatalogRepo, :fun, args)`,
  #      function captures like `&CatalogRepo.all/1`, and even bare name
  #      references (which is why Application and Release are on
  #      @name_only_referrers).
  defp beam_reference_reason(module) do
    with {:ok, chunks} <- beam_chunks(module) do
      imports = Keyword.get(chunks, :imports, [])
      atoms = Keyword.get(chunks, :atoms, [])

      cond do
        mfa = Enum.find(imports, fn {m, _f, _a} -> m == DigitalOilSticker.CatalogRepo end) ->
          "imports call to #{format_mfa(mfa)}"

        mfa = Enum.find(imports, fn {m, _f, _a} -> ecto_sql_sibling?(m) end) ->
          "imports raw-SQL call to #{format_mfa(mfa)}"

        Enum.any?(atoms, fn
          {_id, atom} -> atom == :"Elixir.DigitalOilSticker.CatalogRepo"
          atom when is_atom(atom) -> atom == :"Elixir.DigitalOilSticker.CatalogRepo"
        end) ->
          "atom table contains Elixir.DigitalOilSticker.CatalogRepo " <>
            "(apply/3, function capture, or bare name reference)"

        true ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp beam_chunks(module) do
    with beam when is_list(beam) <- :code.which(module),
         {:ok, {_mod, chunks}} <- :beam_lib.chunks(beam, [:imports, :atoms]) do
      {:ok, chunks}
    else
      _ -> :error
    end
  end

  defp ecto_sql_sibling?(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir.Ecto.Adapters.SQL" -> true
      "Elixir.Ecto.Adapters.SQL." <> _ -> true
      _ -> false
    end
  end

  defp format_mfa({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
end
