defmodule DigitalOilSticker.NoPersonalPersistenceTest do
  @moduledoc """
  The DOS-M09-007 FR-13 and FR-16 release gate: the server has nowhere to put
  personal data, and nothing in the release phones home.

  INV-23 is the product's central claim — the user's garage lives in the user's
  browser and the server never holds it. Revision 1.0.0 backed that with a
  physical fact (the endpoint bound 127.0.0.1). ADR-0004 retired that fact, so
  the claim now rests on code and configuration, which is "weaker in kind and
  therefore must be stronger in detail". These tests are the detail.

  The failure mode being guarded is not a malicious commit. It is an ordinary
  one: `mix phx.gen.schema` to "just cache the selected vehicle", a generator
  re-adding `priv/repo/seeds.exs`, a well-meant `{:sentry, "~> 10.0"}` after a
  bad night of production errors, a Google Font pasted into the layout. Each of
  those is a two-minute change that quietly converts a privacy claim into a
  false one, and none of them look like a security incident in review. Here
  each one is a red build.

  ## What these tests do not cover

  They assert structure, not runtime behaviour. That the repo actually refuses
  writes is `DigitalOilSticker.Catalog.RepoReadonlyTest`; that no personal value
  reaches a log line is the scripted-session gate; that the CSP actually blocks
  a third-party origin at request time belongs to the security-header tests.
  What is asserted here is that the shapes which would make those failures
  possible do not exist in the tree at all.
  """
  use ExUnit.Case, async: true

  alias DigitalOilStickerWeb.Hosts

  @app_root Path.expand("../..", __DIR__)
  @lib Path.expand("../../lib", __DIR__)
  @web Path.expand("../../lib/digital_oil_sticker_web", __DIR__)
  @assets Path.expand("../../assets", __DIR__)
  @config Path.expand("../../config", __DIR__)

  # Normalising line endings keeps the multi-line block regexes below working
  # when a checkout on Windows hands back CRLF.
  defp read(path), do: path |> File.read!() |> String.replace("\r\n", "\n")

  defp rel(path), do: Path.relative_to(path, @app_root)

  # Comments explaining why something is absent must not read as declaring it —
  # the same crude full-line strip DeployConfigTest uses on fly.toml, for the
  # same reason. It does not handle a `#` inside a string literal, which is
  # acceptable: the tokens being searched for are mechanism names, not prose.
  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end

  describe "FR-13: the server has no place to put personal data" do
    test "the configured repo list is exactly the read-only catalog" do
      # Asserted against the loaded application environment rather than the text
      # of config.exs, because the environment is what the running release acts
      # on. A second repo here is the single change that would give personal
      # data somewhere on the server to land.
      assert Application.fetch_env!(:digital_oil_sticker, :ecto_repos) == [
               DigitalOilSticker.CatalogRepo
             ]
    end

    test "no module anywhere in lib defines an Ecto schema" do
      # A schema is the shape of a table. The only table this application has is
      # the read-only catalog, and the catalog is queried through hand-written
      # SQL and plain structs precisely so that no schema module exists to be
      # extended with a `vehicles` or `service_records` table later.
      sources = lib_sources()

      # The walk must reach real code, or every assertion below passes on an
      # empty list. The tree is ~57 files today; the floor is deliberately loose
      # so ordinary churn does not trip it, but a broken glob returns zero.
      assert length(sources) > 40,
             "the lib walk found only #{length(sources)} files — the glob is wrong, " <>
               "and every absence assertion below would pass vacuously"

      # Positive control: the scanner can in fact see a `use Ecto.X` line, so a
      # clean result below means "no schema", not "regex silently broken by an
      # edit". CatalogRepo is the one and only file that must match.
      repo_modules =
        for {path, source} <- sources, source =~ ~r/^\s*use\s+Ecto\.Repo\b/m, do: path

      assert Enum.map(repo_modules, &Path.basename/1) == ["catalog_repo.ex"],
             "expected exactly one `use Ecto.Repo` in lib, found: #{inspect(repo_modules)}"

      schema_patterns = [
        ~r/^\s*use\s+Ecto\.Schema\b/m,
        ~r/^\s*embedded_schema\s+do\b/m,
        ~r/^\s*schema\s+"/m
      ]

      offenders =
        for {path, source} <- sources,
            Enum.any?(schema_patterns, &(source =~ &1)),
            do: path

      assert offenders == [],
             "these modules declare an Ecto schema — the server persists no user data, " <>
               "so there is no table for one to describe: #{Enum.join(offenders, ", ")}"
    end

    test "there is no migrations directory and no migration script under priv" do
      # A migration is a write to a database this application does not have. The
      # catalog is a build artifact produced by tools/catalog and shipped
      # read-only inside the image; nothing in the release may alter it.
      refute File.exists?(Path.join(@app_root, "priv/repo")),
             "priv/repo exists — the only repo is a read-only build artifact"

      refute File.exists?(Path.join(@app_root, "priv/repo/migrations")),
             "a migrations directory exists"

      scripts = Path.wildcard(Path.join(@app_root, "priv/**/*.exs"))

      assert scripts == [],
             "executable scripts under priv/ can only be migrations or seeds here: " <>
               "#{Enum.join(Enum.map(scripts, &rel/1), ", ")}"

      # Non-vacuous: priv itself must exist and hold the catalog artifact, or the
      # wildcard above is searching an empty tree and proves nothing.
      assert File.dir?(Path.join(@app_root, "priv/catalog")),
             "priv/catalog is missing — the assertions above searched nothing"

      migration_modules =
        for {path, source} <- lib_sources(), source =~ ~r/\bEcto\.Migration\b/, do: path

      assert migration_modules == [],
             "these modules reference Ecto.Migration: #{Enum.join(migration_modules, ", ")}"
    end

    test "there is no seeds file" do
      # Seeds are the generator's habitual companion to migrations, and the file
      # is where a "just one row for testing" personal record would first appear.
      seeds =
        (Path.wildcard(Path.join(@app_root, "priv/seeds*")) ++
           Path.wildcard(Path.join(@app_root, "priv/**/seeds*")) ++
           Path.wildcard(Path.join(@app_root, "lib/**/seeds*")))
        |> Enum.uniq()

      assert seeds == [],
             "a seeds file exists: #{Enum.join(Enum.map(seeds, &rel/1), ", ")}"
    end

    test "no backup, dump, or replication job is configured" do
      # Backing up a server that holds no personal data is harmless; the hazard
      # is that adding a backup job is how a server *starts* holding it, and how
      # a copy of the catalog machine's disk starts being retained somewhere
      # outside the release image. There is nothing here worth backing up, so
      # any of these tokens appearing means the shape of the deployment changed
      # without the privacy claim being revisited.
      mechanisms = [
        "pg_dump",
        "pg_restore",
        "pg_basebackup",
        "mysqldump",
        "litestream",
        "restic",
        "duplicity",
        "rsync",
        "VACUUM INTO",
        "ecto.dump",
        "ecto.load",
        "ecto.migrate",
        "ecto.rollback"
      ]

      scanned =
        Path.wildcard(Path.join(@config, "*.exs")) ++
          Path.wildcard(Path.join(@lib, "**/*.{ex,heex}")) ++
          [Path.join(@app_root, "mix.exs"), Path.join(@app_root, "fly.toml")]

      assert length(scanned) > 40,
             "the backup scan walked only #{length(scanned)} files — the globs are wrong"

      offenders =
        for path <- scanned,
            directives = path |> read() |> strip_comments(),
            mechanism <- mechanisms,
            String.contains?(String.downcase(directives), String.downcase(mechanism)),
            do: "#{rel(path)}: #{mechanism}"

      assert offenders == [],
             "a backup or database-lifecycle job is configured: #{Enum.join(offenders, ", ")}"
    end

    test "every environment that configures the catalog repo opens it read-only" do
      # Read as text, deliberately: only one environment's repo config is loaded
      # in any given test run, so asserting on the live Application env can only
      # ever prove :test. The other two are exactly the ones that matter — dev
      # points at the real corpus, and prod's block in runtime.exs is what the
      # release runs. `mode: :readonly` is SQLITE_OPEN_READONLY, the layer below
      # both `read_only: true` and PRAGMA query_only; that it holds at runtime is
      # DigitalOilSticker.Catalog.RepoReadonlyTest's job, not this one's.
      blocks =
        for path <- Path.wildcard(Path.join(@config, "*.exs")),
            source = read(path),
            captures =
              Regex.scan(
                ~r/config :digital_oil_sticker,\s*DigitalOilSticker\.CatalogRepo,(.*?)\n\n/s,
                source
              ),
            [_, block] <- captures,
            do: {Path.basename(path), block}

      files = blocks |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

      # Every environment the application actually runs in must be represented,
      # or a missing block would read as a pass.
      assert files == ["dev.exs", "runtime.exs", "test.exs"],
             "expected a CatalogRepo config block in dev, test, and prod (runtime.exs); found: " <>
               inspect(files)

      for {file, block} <- blocks do
        assert block =~ ~r/mode:\s*:readonly/,
               "#{file} configures CatalogRepo without mode: :readonly"

        # journal_mode must be nil for the same reason: ecto_sqlite3 otherwise
        # defaults to :wal, and `PRAGMA journal_mode = wal` writes the file
        # header, which a read-only handle cannot do.
        assert block =~ ~r/journal_mode:\s*nil/,
               "#{file} leaves journal_mode to the adapter default (:wal), which writes"
      end
    end
  end

  describe "FR-16: nothing in the release reports to a third party" do
    test "no analytics, session-recording, advertising, error-reporting, or beaconing dependency" do
      # Third-party error reporting is the one of these with a real argument
      # behind it, and it is still refused here. LiveView assigns hold the user's
      # decoded garage — vehicle names, odometer readings, service dates, notes —
      # for the whole socket lifetime, and every crash reporter's default
      # behaviour is to serialise the crashing process's state. Adding one would
      # ship exactly the data INV-23 promises never leaves the browser, in the
      # payload nobody thinks to read. If it is ever wanted it needs an ADR
      # recording the trade, plus a scrubbing layer between assigns and the
      # reporter that is itself proven by test — not a dependency line.
      forbidden = %{
        "analytics" =>
          ~w(google_analytics plausible posthog mixpanel segment amplitude matomo heap_analytics),
        "session recording" => ~w(fullstory hotjar logrocket smartlook mouseflow),
        "advertising" =>
          ~w(adroll adsense doubleclick google_ads facebook_pixel taboola outbrain),
        "third-party error reporting" =>
          ~w(sentry appsignal honeybadger rollbar bugsnag new_relic newrelic datadog raygun),
        "beaconing" => ~w(beacon pingdom uptimerobot phone_home)
      }

      declared =
        Mix.Project.config()
        |> Keyword.fetch!(:deps)
        |> Enum.map(&(&1 |> elem(0) |> Atom.to_string()))

      # The lock is the honest list: a reporter pulled in transitively still
      # runs, and would never appear in mix.exs.
      locked =
        @app_root
        |> Path.join("mix.lock")
        |> read()
        |> then(&Regex.scan(~r/^\s*"([a-z0-9_]+)":/m, &1))
        |> Enum.map(fn [_, name] -> name end)

      assert "phoenix" in declared, "the declared dep list was not parsed"
      assert "phoenix" in locked and length(locked) > 20, "mix.lock was not parsed"

      offenders =
        for name <- Enum.uniq(declared ++ locked),
            {category, tokens} <- forbidden,
            token <- tokens,
            String.contains?(name, token),
            do: "#{name} (#{category})"

      assert offenders == [],
             "these dependencies send data off the user's device or this machine: " <>
               Enum.join(offenders, ", ")
    end

    test "phoenix_live_dashboard is absent from the declared deps and from the lock" do
      # It was removed outright rather than scoped to [:dev, :test]: `if` compiles
      # both branches, so the router's dev-only block required the module in every
      # environment. It is a debug UI that exposes process state, ETS contents,
      # and a log tap, and it has no business in a production release.
      # DeployConfigTest asserts on the text of mix.exs and the router; this
      # asserts on the resolved tree, where a transitive reappearance would show.
      declared =
        Mix.Project.config()
        |> Keyword.fetch!(:deps)
        |> Enum.map(&(&1 |> elem(0) |> Atom.to_string()))

      locked =
        @app_root
        |> Path.join("mix.lock")
        |> read()
        |> then(&Regex.scan(~r/^\s*"([a-z0-9_]+)":/m, &1))
        |> Enum.map(fn [_, name] -> name end)

      assert "phoenix_live_view" in locked, "mix.lock was not parsed"

      refute "phoenix_live_dashboard" in declared
      refute "phoenix_live_dashboard" in locked
    end

    test "no stylesheet, script, or font is loaded from a third-party origin" do
      # A CDN reference is a per-visit disclosure: the user's IP, User-Agent, and
      # the referring page go to a company the user never chose, on a request the
      # page cannot see fail. It is also the one thing that would force
      # 'unsafe-inline' or a third-party host into the CSP, which is what FR-2
      # exists to prevent. Fonts and icons are vendored (assets/vendor) so the
      # policy can stay first-party only.
      sources = front_end_sources()

      assert length(sources) > 10,
             "the front-end walk found only #{length(sources)} files — the globs are wrong"

      assert Enum.any?(sources, fn {path, _} -> Path.basename(path) == "root.html.heex" end),
             "the walk missed the root layout, which is where a CDN tag would be added"

      # Each captures the host only, so it can be compared against Hosts below.
      # http as well as https: an http reference on a force_ssl app is a mixed
      # content bug and a third-party disclosure at once.
      patterns = [
        ~r/\b(?:src|href|xlink:href)\s*=\s*[{("']*\s*https?:\/\/([a-z0-9.\-]+)/i,
        ~r/@import\s+(?:url\()?\s*["']?https?:\/\/([a-z0-9.\-]+)/i,
        ~r/\burl\(\s*["']?https?:\/\/([a-z0-9.\-]+)/i,
        ~r/\bfrom\s+["']https?:\/\/([a-z0-9.\-]+)/i,
        ~r/\bimport\s*\(\s*["']https?:\/\/([a-z0-9.\-]+)/i
      ]

      # Positive control on the scanner itself. Without this, a typo in any
      # pattern above turns the whole test into a tautology that still passes.
      sample = ~s|<link href="https://fonts.googleapis.com/css2?family=Inter" />|

      detected =
        Enum.find_value(patterns, fn pattern ->
          case Regex.run(pattern, sample) do
            [_, host] -> host
            _ -> nil
          end
        end)

      assert detected == "fonts.googleapis.com",
             "the scanner cannot recognise a CDN link tag, so a clean result below proves nothing"

      # Hosts is the single source of truth for what "ours" means, shared with
      # check_origin and the CSP connect-src. Restating the hostname here would
      # let this test keep passing after the real list moved on.
      first_party = Hosts.production() ++ Hosts.planned()

      offenders =
        for {path, source} <- sources,
            pattern <- patterns,
            [_, host] <- Regex.scan(pattern, source),
            String.downcase(host) not in first_party,
            do: "#{path}: #{host}"

      assert offenders == [],
             "these load a resource from an origin the user did not choose: " <>
               Enum.join(Enum.uniq(offenders), ", ")
    end

    test "no known CDN hostname appears anywhere in the front-end sources" do
      # Broader and blunter than the attribute scan above, and intentionally so:
      # it catches a CDN URL reached by a form the patterns do not model — a
      # `fetch`, a `new FontFace`, a string built at runtime, a preconnect hint.
      # The cost is that a doc comment merely mentioning one of these would fail
      # the test. That is the right trade: a comment naming jsdelivr in this tree
      # is worth a human look.
      cdns = ~w(googleapis gstatic cdnjs jsdelivr unpkg cloudflare bootstrapcdn fontawesome)

      sources = front_end_sources()
      assert length(sources) > 10, "the front-end walk found nothing to scan"

      offenders =
        for {path, source} <- sources,
            cdn <- cdns,
            String.contains?(String.downcase(source), cdn),
            do: "#{path}: #{cdn}"

      assert offenders == [],
             "a third-party CDN is referenced: #{Enum.join(offenders, ", ")}"
    end
  end

  # Every compiled and templated source in lib, as {relative_path, contents}.
  defp lib_sources do
    @lib
    |> Path.join("**/*.{ex,heex}")
    |> Path.wildcard()
    |> Enum.map(&{rel(&1), read(&1)})
  end

  # Everything that can put a URL in front of a browser: the asset sources of
  # every extension, plus the web templates and components that render markup.
  # Deliberately reads the sources rather than the built priv/static output,
  # because the source is where a reviewer would have to catch the change.
  defp front_end_sources do
    (Path.wildcard(Path.join(@assets, "**/*")) ++
       Path.wildcard(Path.join(@web, "**/*.{ex,heex}")))
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&{rel(&1), read(&1)})
  end
end
