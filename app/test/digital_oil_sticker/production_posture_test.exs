defmodule DigitalOilSticker.ProductionPostureTest do
  @moduledoc """
  DOS-M09-007 FR-11, FR-12 and FR-17: the parts of the hosted security boundary
  that are made of absence rather than of code.

  Revision 1.0.0 protected personal data with a physical fact — the endpoint
  bound 127.0.0.1, so nothing off-device could reach it. ADR-0004 retired that
  promise, and the replacement is "weaker in kind and therefore must be stronger
  in detail". Most of that detail is a thing NOT happening: a parameter not
  logged, a stack trace not rendered, a debug UI not mounted, a secret not
  checked in, a distribution port not opened. Absences have no author and no
  owner, so nothing stops a generator, an upgrade, or a hurried debugging
  session from filling them back in. This file is what notices.

  Where possible the assertion runs against the real artifact rather than a
  string in a file: the evaluated production config rather than a regex over
  `config/prod.exs`, the compiled route table rather than a grep of the router,
  the error views actually invoked with hostile assigns rather than a claim that
  they ignore them. A test carrying its own copy of a value passes while the
  real one rots.

  Async is off because two tests set and restore `SECRET_KEY_BASE` in the OS
  environment to prove `config/runtime.exs` fails closed without it.

  What this file does NOT cover: it says nothing about what the running
  application logs under load (FR-11's release gate is the scripted-session log
  scan, not this), and nothing about the headers, CSP, CSRF or rate limits —
  those have their own tests.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  @app_root Path.expand("../..", __DIR__)

  # Call sites that can put a value into a log sink. `IO.puts`/`IO.inspect`/
  # `dbg` matter as much as Logger here: on Fly, stdout IS the log stream, so a
  # debugging line left behind is a published line. The leading lookbehind stops
  # `Phoenix.LiveDashboard.RequestLogger` and friends from matching the word
  # "Logger"; it also means a call qualified through an alias
  # (`MyApp.Logger.info`) would be missed, which is accepted — nothing in this
  # codebase wraps Logger.
  @log_call ~r/(?<![\w.])(?:Logger\.\w+|IO\.(?:inspect|puts|write|warn)|dbg)\s*\(/

  # The values this application handles are odometer readings, service dates,
  # notes, and vehicle identifiers. They travel as `params`, live in `assigns`,
  # and are carried across the wire in the local-store `envelope` — so a log
  # line naming any of those is a log line that can carry them.
  @payload_words ~r/\b(?:assigns|params|garage|envelope|payload)\b/

  # A base64-ish run long enough to be key material rather than an identifier.
  @secret_literal ~r/"[A-Za-z0-9+\/]{40,}={0,2}"/

  # config/dev.exs and config/test.exs carry the generator's local key bases.
  # They are the only checked-in secret-shaped literals that are allowed, and
  # they are allowed only because the Dockerfile never copies those two files
  # into the image — asserted below, so this exemption cannot outlive its
  # justification.
  @local_key_base_files ["config/dev.exs", "config/test.exs"]

  setup_all do
    %{
      # The evaluated production config, not a regex over the file. This is what
      # the release actually starts with.
      prod: Config.Reader.read!(Path.join(@app_root, "config/prod.exs"), env: :prod),
      merged_prod: Config.Reader.read!(Path.join(@app_root, "config/config.exs"), env: :prod),
      fly_directives: @app_root |> Path.join("fly.toml") |> File.read!() |> strip_comments("#"),
      dockerfile: @app_root |> Path.join("Dockerfile") |> File.read!()
    }
  end

  describe "FR-11: nothing the user typed can reach a log sink" do
    test "every request parameter is dropped, rather than filtered by name", %{
      merged_prod: merged
    } do
      # Phoenix's default is a denylist of common credential names — "password",
      # "token", "secret". That list is exactly wrong here: this application has
      # no credentials, and the values worth protecting are an odometer reading,
      # a service date, a free-text note and a vehicle identifier, which arrive
      # under names no generic denylist has ever heard of. `{:keep, []}` inverts
      # the rule: keep nothing, drop everything, and let the allowlist grow by
      # review if support ever genuinely needs a non-personal parameter.
      assert Application.fetch_env!(:phoenix, :filter_parameters) == {:keep, []}

      # The line above proves it for the test VM. This proves it for the release:
      # config.exs merged under MIX_ENV=prod, which is what the image compiles.
      assert merged[:phoenix][:filter_parameters] == {:keep, []}
    end

    test "the production logger level is above :debug", %{prod: prod} do
      # Phoenix logs "Parameters: %{...}" at :debug, and LiveView logs mount and
      # handle_event payloads at :debug. Every route in this router is dispatched
      # at :debug too (asserted below). So the level is not a verbosity
      # preference here — it is the switch that decides whether user data is
      # written down at all.
      assert Keyword.has_key?(prod[:logger] || [], :level),
             "config/prod.exs does not set a logger level, so the release inherits the default"

      level = prod[:logger][:level]

      assert Logger.compare_levels(level, :debug) == :gt,
             "production logger level is #{inspect(level)}; at :debug Phoenix writes request " <>
               "parameters and LiveView event payloads to the log"
    end

    test "no route asks to be logged above :debug" do
      routes = DigitalOilStickerWeb.Router.__routes__()

      assert length(routes) > 0, "the router compiled to no routes at all"

      offenders =
        Enum.reject(routes, fn route ->
          log = route.metadata[:log]
          log == false or Logger.compare_levels(log, :debug) == :eq
        end)

      # A route may override its own log level. One that did would be logged in
      # production despite the :info level above, carrying its parameters with
      # it — a hole punched through the previous test without touching it.
      assert offenders == [],
             "these routes log above :debug and would emit their parameters in production: " <>
               inspect(Enum.map(offenders, &{&1.path, &1.metadata[:log]}))
    end

    test "no log call in lib/ names a payload" do
      sources = lib_sources()

      # Without this the whole test is a claim about an empty list.
      assert length(sources) > 20,
             "the source walk found only #{length(sources)} files under lib/ — the glob is wrong"

      offenders =
        for {file, line, call} <- log_call_sites(sources), Regex.match?(@payload_words, call) do
          "#{relative(file)}:#{line}"
        end

      assert offenders == [],
             "these log calls can carry personal data (odometer, date, note, vehicle) into a " <>
               "log sink: #{Enum.join(offenders, ", ")}"
    end

    test "the payload scan has real log calls to scan, so it is not vacuous" do
      # This replaces an earlier assertion that lib/ contained NO log call at
      # all, which was true when the suite was written and left the scan above
      # with nothing to reject. The first Logger call arrived with the CSP
      # report sink; that test's own instructions were to delete it and let the
      # scan take over as the live guard, which is what happened.
      #
      # What is asserted now is the property that actually matters: there is
      # something to scan, so a future call that interpolates a payload has a
      # working guard rather than a dormant one.
      sites = log_call_sites(lib_sources())

      assert sites != [],
             "lib/ contains no log call at all, so the payload scan above rejects nothing " <>
               "and would not notice a call that leaked one"
    end
  end

  describe "FR-12: an error tells the client its status and nothing else" do
    test "stack traces and code reloading are switched off explicitly, not inherited", %{
      prod: prod
    } do
      endpoint = prod[:digital_oil_sticker][DigitalOilStickerWeb.Endpoint]

      # `Keyword.has_key?` is the assertion, not the value: both of these happen
      # to default to false, so a regex or a value check would pass on a
      # config/prod.exs that says nothing at all. Whether a stack trace and the
      # source excerpt around it reach the internet is not a thing to leave to a
      # framework default that a Phoenix upgrade is free to change.
      #
      # DeployConfigTest asserts the same two lines by regex over the file. This
      # asserts them against the evaluated config, which is what the release
      # reads; the overlap is deliberate.
      assert Keyword.has_key?(endpoint, :debug_errors),
             "config/prod.exs does not mention debug_errors — it is inheriting the default"

      assert Keyword.has_key?(endpoint, :code_reloader),
             "config/prod.exs does not mention code_reloader — it is inheriting the default"

      assert endpoint[:debug_errors] == false
      assert endpoint[:code_reloader] == false
    end

    test "the error views cannot serialise the assigns they are handed" do
      # Phoenix hands the error view everything it knows: the conn (with the
      # request's assigns on it), the exception, the stacktrace. The generated
      # views ignore all of it, and this is the assertion that they still do —
      # invoked for real, with a marker planted in every assign a customised
      # view would reach for first.
      marker = "e4f1c0de-only-in-assigns"

      assigns = %{
        conn: %{assigns: %{garage: %{"vin" => marker}}, params: %{"odometer" => marker}},
        reason: %RuntimeError{message: marker},
        stack: [{DigitalOilSticker, :boom, 1, [file: ~c"lib/#{marker}.ex", line: 1]}],
        kind: :error,
        status: 500
      }

      html = DigitalOilStickerWeb.ErrorHTML.render("500.html", assigns)
      json = DigitalOilStickerWeb.ErrorJSON.render("500.json", assigns)

      assert html == "Internal Server Error"
      assert json == %{errors: %{detail: "Internal Server Error"}}

      refute html =~ marker
      refute inspect(json) =~ marker

      # The same for a 404, which is the one a crawler will actually see.
      assert DigitalOilStickerWeb.ErrorHTML.render("404.html", assigns) == "Not Found"
    end

    test "the error view sources reference neither assigns nor inspect/1" do
      for file <- ["error_html.ex", "error_json.ex"] do
        path = Path.join(@app_root, "lib/digital_oil_sticker_web/controllers/#{file}")
        code = path |> File.read!() |> strip_comments("#")

        # Both files ship with a commented-out block showing how to customise a
        # status code, and error_html.ex with a commented `embed_templates`.
        # Comments are stripped first: the hazard is uncommenting them, not
        # having them there to read.
        assert code =~ "status_message_from_template",
               "#{file} no longer renders the plain status message"

        assert code =~ "_assigns",
               "#{file} no longer discards its assigns"

        # `\bassigns\b` cannot match inside `_assigns` (underscore is a word
        # character), so this catches a view that started using them.
        refute code =~ ~r/\bassigns\b/, "#{file} reads its assigns"
        refute code =~ "@conn", "#{file} reaches into the conn"
        refute code =~ "inspect", "#{file} inspects a value into the response"
        refute code =~ "Exception.", "#{file} formats an exception into the response"
        refute code =~ "embed_templates", "#{file} renders a template that could read assigns"
      end
    end

    test "errors render with no layout, through the two audited views" do
      render_errors =
        Application.fetch_env!(:digital_oil_sticker, DigitalOilStickerWeb.Endpoint)[
          :render_errors
        ]

      # `layout: false` matters as much as the views themselves: a layout would
      # run the application's root layout against the error assigns, and the root
      # layout is a file people edit freely without thinking about the 500 path.
      assert render_errors[:layout] == false

      assert render_errors[:formats] == [
               html: DigitalOilStickerWeb.ErrorHTML,
               json: DigitalOilStickerWeb.ErrorJSON
             ]
    end

    test "an unrouted request returns the plain status text end to end", %{conn: conn} do
      # The two tests above check the views in isolation and the config in
      # isolation. This one is the only place the whole path is exercised: an
      # unmatched request through the real endpoint, the real error handler, and
      # the configured view.
      #
      # No `assert_error_sent`: Phoenix renders a NoRouteError and, alone among
      # exceptions, does not re-raise it, so this arrives as an ordinary 404
      # response.
      conn = get(conn, "/no-such-path")

      assert response(conn, 404) == "Not Found"

      # The body is the whole body. A stack trace, the request path echoed back,
      # or a debug page would all be longer than this.
      assert byte_size(conn.resp_body) == byte_size("Not Found")
    end
  end

  describe "FR-17: no operator surface is exposed to the internet" do
    test "the live dashboard is absent as an application, a lock entry, and a route" do
      # `Application.spec/2` returns nil for an application that is not installed
      # — the strongest form of this assertion, because it asks the running
      # system rather than a file. mix.lock is checked too: a transitive
      # dependency would appear there without appearing in mix.exs.
      assert Application.spec(:phoenix_live_dashboard, :vsn) == nil,
             "phoenix_live_dashboard is installed in this build"

      lock = @app_root |> Path.join("mix.lock") |> File.read!()
      refute lock =~ "phoenix_live_dashboard", "phoenix_live_dashboard is in mix.lock"

      routes = DigitalOilStickerWeb.Router.__routes__()

      for route <- routes do
        refute inspect(route.plug) =~ "LiveDashboard",
               "#{route.path} dispatches to the live dashboard"

        refute String.starts_with?(route.path, "/dev"),
               "#{route.path} is a development route in the compiled route table"
      end
    end

    test "no route dispatches to a plug from outside this application" do
      routes = DigitalOilStickerWeb.Router.__routes__()

      assert length(routes) > 0, "the router compiled to no routes at all"

      # Phoenix.LiveView.Plug is the router's own entry point for `live` routes,
      # so it is ours in everything but name. Anything else third-party mounted
      # here — a dashboard, a mailbox preview, a metrics UI — is an operator
      # surface on a public hostname, which is the thing FR-17 is about. New
      # DigitalOilStickerWeb routes are free to appear without touching this.
      offenders =
        Enum.reject(routes, fn route ->
          route.plug == Phoenix.LiveView.Plug or
            String.starts_with?(inspect(route.plug), "DigitalOilStickerWeb.")
        end)

      assert offenders == [],
             "these routes mount a plug from outside the application: " <>
               inspect(Enum.map(offenders, &{&1.path, &1.plug}))
    end

    test "no dev_routes switch survives in config or in code" do
      sources = config_sources() ++ lib_sources()

      assert length(sources) > 20,
             "the source walk found only #{length(sources)} files — the glob is wrong"

      offenders =
        for file <- sources,
            code = file |> File.read!() |> strip_comments("#"),
            code =~ "dev_routes",
            do: relative(file)

      # The generator gates the dashboard behind a `dev_routes` flag. The gate
      # never worked as advertised — `if` compiles both branches, so the
      # dependency shipped regardless — and the route it guarded is gone. A flag
      # left lying around invites someone to switch it on. Comments naming it
      # (there are two, explaining why it is absent) are stripped first, so
      # documenting the absence does not read as declaring it.
      assert offenders == [], "dev_routes is still referenced in: #{Enum.join(offenders, ", ")}"

      assert Application.get_env(:digital_oil_sticker, :dev_routes) == nil
    end

    test "nothing in the release, the image, or the platform config enables distribution", %{
      fly_directives: fly,
      dockerfile: docker
    } do
      rel_files =
        @app_root
        |> Path.join("rel/**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)

      assert length(rel_files) > 0,
             "rel/ holds no files at all — the release no longer carries its own launcher"

      # A vm.args template is where `-name`/`-sname`/`-setcookie` would live.
      # There is none, so the release takes its node settings from the
      # environment alone.
      assert Enum.filter(rel_files, &(Path.basename(&1) =~ ~r/vm\.args/)) == [],
             "rel/ now carries a vm.args template — read it, it sets the node's identity"

      for file <- rel_files do
        # Comments stripped: the generated rel/env.sh ships every distribution
        # option commented out as documentation, and reading them must not count
        # as setting them. `=none` is deliberately absent from these tokens —
        # turning distribution off is the fix, not the defect.
        directives = file |> File.read!() |> strip_comments("#")

        for token <- [
              "-name ",
              "-sname ",
              "-setcookie",
              "RELEASE_DISTRIBUTION=name",
              "RELEASE_DISTRIBUTION=sname",
              "RELEASE_COOKIE="
            ] do
          refute directives =~ token, "#{relative(file)} sets #{token}"
        end

        # `start` runs the release. `start_iex`, `daemon_iex`, `remote` and `rpc`
        # are the ways the launcher can instead hand someone a shell inside the
        # production node.
        for token <- ["start_iex", "daemon_iex", " remote", " rpc"] do
          refute directives =~ token,
                 "#{relative(file)} launches an interactive or remote mode"
        end
      end

      for {label, pattern} <- [
            # name/sname start distribution; none is the fix, so it is allowed
            # through here.
            {"RELEASE_DISTRIBUTION", ~r/RELEASE_DISTRIBUTION\s*=\s*"?s?name/},
            {"RELEASE_NODE", ~r/RELEASE_NODE/},
            {"RELEASE_COOKIE", ~r/RELEASE_COOKIE/},
            {"ERL_AFLAGS", ~r/ERL_AFLAGS/}
          ] do
        refute fly =~ pattern, "fly.toml sets #{label}"
        refute docker =~ pattern, "the Dockerfile sets #{label}"
      end

      # epmd. Only the ports in [http_service] are reachable from the internet,
      # but an explicit mapping would change that.
      refute fly =~ "4369"

      assert docker =~ ~s(CMD ["/app/bin/server"]),
             "the image no longer starts through the plain server launcher"

      mix = @app_root |> Path.join("mix.exs") |> File.read!()
      refute mix =~ "cookie:", "mix.exs pins a release cookie"
    end

    test "the release turns Erlang distribution off" do
      # This was skipped as a genuine gap when the suite was written, and the
      # gap has since been closed. `mix release` defaults RELEASE_DISTRIBUTION
      # to "sname", so the release started epmd and a distributed node with the
      # cookie baked into the image — on purely because it is the default, since
      # DNSCluster is `:ignore`, PubSub is local, and nothing calls Node or
      # :rpc. The test above can only prove no file *enables* distribution;
      # this one proves something turns it off.
      #
      # The template is `rel/env.sh.eex`, not `rel/env.sh`: Elixir renders the
      # .eex into the release, and a plain env.sh is ignored — which would fail
      # silently, leaving distribution on while this test read as green.
      env_sh = Path.join(@app_root, "rel/env.sh.eex")

      assert File.exists?(env_sh),
             "rel/env.sh.eex does not exist, so mix release's sname default applies"

      assert File.read!(env_sh) =~ "RELEASE_DISTRIBUTION=none"
    end

    test "the clustering child is inert and has nothing to query", %{fly_directives: fly} do
      children = Supervisor.which_children(DigitalOilSticker.Supervisor)

      # DNSCluster is the one thing in the supervision tree that would connect
      # nodes. With no query it returns :ignore from start_link, and the
      # supervisor records the child with an :undefined pid — it is not running.
      assert {DNSCluster, :undefined, _type, _mods} =
               List.keyfind(children, DNSCluster, 0),
             "DNSCluster is running: #{inspect(List.keyfind(children, DNSCluster, 0))}"

      # That holds in production only as long as nothing supplies the query.
      refute fly =~ "DNS_CLUSTER_QUERY", "fly.toml supplies a DNS cluster query"
    end

    test "the production secret key base comes from the environment" do
      sentinel = "sentinel-not-a-real-key-base"
      original = System.get_env("SECRET_KEY_BASE")
      on_exit(fn -> restore_env("SECRET_KEY_BASE", original) end)

      System.put_env("SECRET_KEY_BASE", sentinel)

      config =
        Config.Reader.read!(Path.join(@app_root, "config/runtime.exs"), env: :prod)

      # Reading the value back out of the evaluated production runtime config is
      # the assertion. A literal spliced in anywhere — a "temporary" default, a
      # fallback next to the `||` — would show up here as something other than
      # what the environment supplied.
      assert config[:digital_oil_sticker][DigitalOilStickerWeb.Endpoint][:secret_key_base] ==
               sentinel
    end

    test "config/runtime.exs fails closed when SECRET_KEY_BASE is missing" do
      original = System.get_env("SECRET_KEY_BASE")
      on_exit(fn -> restore_env("SECRET_KEY_BASE", original) end)

      System.delete_env("SECRET_KEY_BASE")

      # Failing closed matters more than it looks. A generated fallback would
      # boot fine and differ per machine and per restart, so every session cookie
      # and every signed LiveView token would be silently invalidated — and the
      # symptom would be users being logged out of nothing in particular, not an
      # obvious crash. Refusing to boot is the loud version.
      assert_raise RuntimeError, ~r/SECRET_KEY_BASE is missing/, fn ->
        Config.Reader.read!(Path.join(@app_root, "config/runtime.exs"), env: :prod)
      end
    end

    test "no secret-shaped literal is checked in beyond the local key bases" do
      sources = config_sources() ++ lib_sources()

      assert length(sources) > 20,
             "the source walk found only #{length(sources)} files — the glob is wrong"

      hits =
        for file <- sources,
            contents = File.read!(file),
            match <- Regex.scan(@secret_literal, contents),
            do: {relative(file), List.first(match)}

      offenders = for {file, _} <- hits, file not in @local_key_base_files, do: file

      assert offenders == [],
             "a secret-shaped literal is checked into: #{Enum.join(Enum.uniq(offenders), ", ")}. " <>
               "If this is a legitimate non-secret constant, it still does not belong in a " <>
               "config or source file that ships."

      # The exemption is only sound while those two files really do hold nothing
      # but a key base. If one of them stops carrying a literal at all, delete it
      # from @local_key_base_files rather than leaving a stale exemption behind.
      for {file, literal} <- hits do
        line =
          sources
          |> Enum.find(&(relative(&1) == file))
          |> File.read!()
          |> String.split(["\r\n", "\n"])
          |> Enum.find(&String.contains?(&1, literal))

        assert line =~ "secret_key_base:",
               "#{file} carries a secret-shaped literal that is not a key base: #{line}"
      end

      assert Enum.sort(Enum.uniq(for {file, _} <- hits, do: file)) == @local_key_base_files,
             "the local key base exemption is stale — found literals in " <>
               inspect(Enum.uniq(for {file, _} <- hits, do: file))
    end

    test "the local key bases never enter the release image", %{dockerfile: docker} do
      # config/dev.exs and config/test.exs each carry a checked-in key base. That
      # is only acceptable because neither is ever copied: the Dockerfile names
      # the three config files it wants, and MIX_ENV is prod. A wholesale
      # `COPY config config` would put both development key bases into the
      # published image, and nothing else in the build would complain.
      assert docker =~ "COPY config/config.exs config/${MIX_ENV}.exs config/",
             "the Dockerfile no longer copies config files by name"

      assert docker =~ "COPY config/runtime.exs config/"

      for wholesale <- ["COPY config config", "COPY config/ config", "COPY . .", "COPY ./ ."] do
        refute docker =~ wholesale,
               "the Dockerfile copies the config directory wholesale (#{wholesale}), which " <>
                 "carries config/dev.exs and config/test.exs into the image"
      end
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp lib_sources, do: Path.wildcard(Path.join(@app_root, "lib/**/*.{ex,heex}"))
  defp config_sources, do: Path.wildcard(Path.join(@app_root, "config/*.exs"))

  defp relative(path), do: Path.relative_to(path, @app_root)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  # Comments explain why a thing is absent, and naming it there must not read as
  # declaring it. Whole-line comments only: a trailing comment on a code line is
  # part of what a reviewer reads on that line anyway.
  defp strip_comments(text, marker) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.map(fn line ->
      if line |> String.trim_leading() |> String.starts_with?(marker), do: "", else: line
    end)
    |> Enum.join("\n")
  end

  # {file, line, call_text} for every log call site in the given files. Comment
  # lines are blanked rather than dropped so the reported line numbers still
  # point at the right place in the file.
  defp log_call_sites(files) do
    Enum.flat_map(files, fn file ->
      lines =
        file
        |> File.read!()
        |> strip_comments("#")
        |> String.split(["\r\n", "\n"])

      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _n} -> Regex.match?(@log_call, line) end)
      |> Enum.map(fn {_line, n} -> {file, n, call_text(lines, n)} end)
    end)
  end

  # A call's arguments can span lines, so the text of a call is its first line
  # plus every following line until the parentheses balance. Capped at 20 lines
  # so an unbalanced line (a paren inside a string, which this does not parse)
  # cannot swallow the rest of the file.
  defp call_text(lines, line_number) do
    lines
    |> Enum.drop(line_number - 1)
    |> Enum.take(20)
    |> Enum.reduce_while({[], 0}, fn line, {acc, depth} ->
      depth = depth + occurrences(line, "(") - occurrences(line, ")")
      acc = [line | acc]

      if depth <= 0, do: {:halt, {acc, depth}}, else: {:cont, {acc, depth}}
    end)
    |> then(fn {acc, _depth} -> acc |> Enum.reverse() |> Enum.join("\n") end)
  end

  defp occurrences(line, char), do: line |> String.graphemes() |> Enum.count(&(&1 == char))
end
