defmodule DigitalOilSticker.DeployConfigTest do
  @moduledoc """
  The deployment posture ratified in ADR-0004, asserted against the files that
  actually configure it (DOS-M09-005 Definition of Done).

  These decisions were argued once and are cheap to undo by accident — a
  generator regenerating `fly.toml`, a copy-pasted `[[mounts]]` block, someone
  re-adding `release_command` to run migrations that do not exist. Every one of
  those would be a production incident discovered by a user. Here they are a
  red build.

  The parsing is deliberately crude string matching rather than a TOML library:
  the assertion is about what the file says, and a dependency that normalises
  the file could paper over the very drift this is looking for.
  """
  use ExUnit.Case, async: true

  @fly_toml Path.expand("../../fly.toml", __DIR__)
  @dockerfile Path.expand("../../Dockerfile", __DIR__)
  @dockerignore Path.expand("../../.dockerignore", __DIR__)

  setup_all do
    fly = File.read!(@fly_toml)

    %{
      fly: fly,
      # Comments explain why things are absent, and naming them there must not
      # read as declaring them. Absence assertions run against directives only.
      fly_directives: strip_comments(fly),
      docker: File.read!(@dockerfile)
    }
  end

  defp strip_comments(toml) do
    toml
    |> String.split(["\r\n", "\n"])
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end

  describe "ADR-0004 hosting posture" do
    test "runs in ord, and in exactly one region", %{fly: fly} do
      assert fly =~ ~r/primary_region\s*=\s*"ord"/

      # A second region would silently double cost and split the user base
      # across machines with no shared state to justify it.
      assert length(Regex.scan(~r/^primary_region/m, fly)) == 1
    end

    test "stays awake: no scale-to-zero", %{fly: fly} do
      # Scale-to-zero drops every live LiveView socket on the way down and adds
      # a cold start to the next visitor. ADR-0004 ratified always-on.
      assert fly =~ ~r/auto_stop_machines\s*=\s*"off"/
      assert fly =~ ~r/min_machines_running\s*=\s*1/
    end

    test "carries no volume", %{fly_directives: fly} do
      # The catalog is baked into the image and read-only. A volume would
      # reintroduce mutable state on a machine that has none by design, and
      # would resurrect the release_command hazard ADR-0004 dissolved.
      refute fly =~ "[[mounts]]"
      refute fly =~ "[mounts]"
    end

    test "runs no release command", %{fly_directives: fly} do
      # There are no migrations: the catalog is a build artifact and the user's
      # records live in their browser. A release_command here would be running
      # something against a database that does not exist.
      refute fly =~ "release_command"
    end

    test "forces https", %{fly: fly} do
      assert fly =~ ~r/force_https\s*=\s*true/
    end

    test "checks readiness separately from liveness", %{fly: fly} do
      # Both must exist. Checking only liveness lets a machine with a broken
      # catalog stay in rotation; checking only readiness restarts the process
      # for a dependency problem it cannot fix by restarting.
      assert fly =~ ~r{path\s*=\s*"/ready"}
      assert fly =~ ~r{path\s*=\s*"/health"}
      assert length(Regex.scan(~r/\[\[http_service\.checks\]\]/, fly)) == 2
    end
  end

  describe "image" do
    test "the runtime stage runs unprivileged", %{docker: docker} do
      assert docker =~ ~r/USER\s+nobody/
    end

    test "base images are pinned by digest, not only by tag", %{docker: docker} do
      # A tag is a moving target: `debian:trixie-20260610-slim` can be
      # republished, so two builds of the same commit are not the same image.
      # A digest is the image.
      for arg <- ["BUILDER_IMAGE", "RUNNER_IMAGE"] do
        line = Regex.run(~r/^ARG #{arg}=.*$/m, docker) |> List.first()

        assert line, "#{arg} is not declared in the Dockerfile"

        assert line =~ ~r/@sha256:[0-9a-f]{64}/,
               "#{arg} is pinned by tag only — two builds of one commit can differ: #{line}"
      end
    end

    test "verifies the catalog artifact at build time", %{docker: docker} do
      # The artifact is the product. Shipping a truncated or swapped one would
      # be invisible until a user got a wrong answer.
      assert docker =~ "catalog-manifest.json"
      assert docker =~ ~r/sha256sum|SHA256|sha256/
    end

    test "no test fixture reaches the runtime image" do
      ignore = File.read!(@dockerignore)

      for fixture <- [
            "catalog-fixture-a.sqlite3",
            "catalog-fixture-b.sqlite3",
            "catalog-fixture-manifest.json"
          ] do
        assert String.contains?(ignore, fixture) or String.contains?(ignore, "catalog-fixture"),
               "#{fixture} is not excluded from the build context"
      end
    end
  end

  describe "production configuration" do
    test "stack traces and code reloading are disabled explicitly, not by default" do
      prod = File.read!(Path.expand("../../config/prod.exs", __DIR__))

      assert prod =~ ~r/debug_errors:\s*false/
      assert prod =~ ~r/code_reloader:\s*false/
    end

    test "the platform probe paths are exempt from the https redirect" do
      prod = File.read!(Path.expand("../../config/prod.exs", __DIR__))

      # Fly reaches the machine over plain HTTP internally; redirecting the
      # probes makes a healthy machine look unhealthy and it gets stopped.
      for path <- ["/health", "/ready", "/version"] do
        assert prod =~ path, "#{path} is not excluded from force_ssl"
      end
    end

    test "the live dashboard is not a dependency at all" do
      mix = File.read!(Path.expand("../../mix.exs", __DIR__))
      router = File.read!(Path.expand("../../lib/digital_oil_sticker_web/router.ex", __DIR__))

      # Scoping it to [:dev, :test] does not work: `if` compiles both branches,
      # so the router's dev-only dashboard block still requires the module in
      # every environment. Removing the route is what removes the dependency —
      # and a debug UI nobody opens has no business in a production release.
      refute mix =~ "phoenix_live_dashboard",
             "phoenix_live_dashboard is still a dependency"

      refute router =~ "live_dashboard",
             "the router still declares a dashboard route"
    end

    test "no request-log tap is mounted" do
      endpoint = File.read!(Path.expand("../../lib/digital_oil_sticker_web/endpoint.ex", __DIR__))

      # LiveDashboard.RequestLogger streams this server's logs to anyone who
      # sets its param or cookie key. The generator mounts it unconditionally.
      refute endpoint =~ ~r/plug Phoenix\.LiveDashboard\.RequestLogger/
    end
  end

  describe "static assets" do
    test "every shipped asset routes through the digest pipeline" do
      # A bare "/images/foo.svg" is served undigested, so it carries no
      # immutable cache header and the browser revalidates it on every visit.
      # Measured on a real tablet: the two sticker SVGs transferred 300 bytes
      # each on every repeat visit while every ~p-routed asset transferred
      # zero. `~p` is what puts the digest in the URL.
      offenders =
        Path.wildcard(Path.expand("../../lib/digital_oil_sticker_web/**/*.{ex,heex}", __DIR__))
        |> Enum.flat_map(fn file ->
          file
          |> File.read!()
          |> then(&Regex.scan(~r/(?:src|href)="\/(?:images|assets|favicon)[^"]*"/, &1))
          |> Enum.map(fn [match] -> "#{Path.basename(file)}: #{match}" end)
        end)

      assert offenders == [],
             "these assets bypass the digest pipeline and will revalidate on every visit " <>
               "(use ~p instead): #{Enum.join(offenders, ", ")}"
    end
  end

  describe "operational endpoints are not content" do
    test "robots.txt excludes them" do
      robots = File.read!(Path.expand("../../priv/static/robots.txt", __DIR__))

      for path <- ["/health", "/ready", "/version"] do
        assert robots =~ "Disallow: #{path}"
      end
    end
  end
end
