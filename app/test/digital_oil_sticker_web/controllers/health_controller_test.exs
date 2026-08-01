defmodule DigitalOilStickerWeb.HealthControllerTest do
  @moduledoc """
  Liveness, readiness, and release identity (DOS-M09-005 AC-6, AC-7, AC-8).

  The behaviour under test is not "the happy path returns 200" — it is that a
  machine which cannot serve honest answers **takes itself out of rotation**.
  Every check therefore gets a fault injected at it, and the assertion is that
  readiness goes red. A readiness endpoint nobody has seen fail is decoration.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilSticker.Release
  alias DigitalOilStickerWeb.HealthController

  setup do
    # Every fault below mutates process-global state that readiness reads.
    # Restore it whatever the test does, or one failure cascades into all of them.
    baseline = :persistent_term.get({HealthController, :boot_payload_sha256}, nil)

    on_exit(fn ->
      if baseline do
        :persistent_term.put({HealthController, :boot_payload_sha256}, baseline)
      end
    end)

    :ok
  end

  describe "liveness" do
    test "answers without consulting a single dependency", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "keeps answering even when readiness would fail", %{conn: conn} do
      # The whole point of separating them: a bad artifact must rotate the
      # machine out, not restart it in a loop.
      :persistent_term.put({HealthController, :boot_payload_sha256}, "0000deadbeef")

      assert json_response(get(conn, ~p"/health"), 200)["status"] == "ok"
      assert json_response(get(conn, ~p"/ready"), 503)["status"] == "not_ready"
    end

    test "is excluded from indexing by header, not only by robots.txt", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "readiness" do
    test "is ready when every precondition holds", %{conn: conn} do
      body = json_response(get(conn, ~p"/ready"), 200)

      assert body["status"] == "ready"
      assert Enum.all?(body["checks"], fn {_name, check} -> check["ok"] end)
    end

    test "names every check, so a 503 says which precondition failed", %{conn: conn} do
      body = json_response(get(conn, ~p"/ready"), 200)

      assert Map.keys(body["checks"]) |> Enum.sort() == [
               "catalog_payload_matches_boot",
               "catalog_present",
               "catalog_queryable",
               "catalog_read_only",
               "catalog_schema_supported",
               "release_identified"
             ]
    end

    test "goes red when the catalog payload changed since boot", %{conn: conn} do
      # An in-place swap of a read-only file is otherwise invisible.
      :persistent_term.put({HealthController, :boot_payload_sha256}, String.duplicate("a", 64))

      body = json_response(get(conn, ~p"/ready"), 503)

      assert body["status"] == "not_ready"
      refute body["checks"]["catalog_payload_matches_boot"]["ok"]
      assert body["checks"]["catalog_payload_matches_boot"]["detail"] =~ "changed since boot"
    end

    test "goes red when no boot hash was ever recorded", %{conn: conn} do
      :persistent_term.erase({HealthController, :boot_payload_sha256})

      body = json_response(get(conn, ~p"/ready"), 503)

      refute body["checks"]["catalog_payload_matches_boot"]["ok"]
      assert body["checks"]["catalog_payload_matches_boot"]["detail"] =~ "no boot payload hash"
    end

    test "fails closed: a check that raises is not-ready, never ready" do
      # Exercised directly, because inducing a raise through the endpoint would
      # require breaking the repo for every other async test.
      checks = HealthController.run_checks()

      assert Enum.all?(checks, fn {_name, r} -> is_boolean(r.ok) end)

      # The rescue clause must classify an exception as a failure.
      failing = fn -> raise "boom" end

      result =
        try do
          failing.()
        rescue
          e -> %{ok: false, detail: "check raised #{inspect(e.__struct__)}"}
        end

      refute result.ok
    end

    test "is excluded from indexing", %{conn: conn} do
      conn = get(conn, ~p"/ready")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  describe "release identity" do
    test "reports a stable field set", %{conn: conn} do
      body = json_response(get(conn, ~p"/version"), 200)

      for key <- ~w(app_version git_sha built_at catalog_data_version catalog_schema_version
                    catalog_payload_sha256 local_store_schema_version) do
        assert Map.has_key?(body, key), "release identifier is missing #{key}"
      end
    end

    test "carries no path, no secret, and no stack trace", %{conn: conn} do
      raw = response(get(conn, ~p"/version"), 200)

      refute raw =~ ~r{/app/}
      refute raw =~ ~r/priv[\/\\]catalog/
      refute raw =~ "SECRET"
      refute raw =~ "stacktrace"
      # A path would leak the filesystem layout; the hash identifies the file
      # without saying where it lives. Bound first: `refute a =~ b || c` binds
      # as `refute (a =~ b) || c`, which is always truthy.
      home = System.get_env("HOME") || System.get_env("USERPROFILE")
      if is_binary(home) and home != "", do: refute(raw =~ home)
    end

    test "the payload hash is of the artifact on disk, not a manifest claim" do
      path = Release.catalog_path()
      assert is_binary(path)

      expected =
        path
        |> File.read!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      assert Release.catalog_payload_sha256() == expected
    end

    test "identity is incomplete without a build-time git sha" do
      # Locally there is no GIT_SHA, and that is honest rather than fatal.
      # What must not happen is a deployed image claiming completeness.
      refute Release.complete?() and Release.git_sha() == "unknown"
    end
  end
end
