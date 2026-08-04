defmodule DigitalOilSticker.LocalStore.MigrationsExtendedTest do
  @moduledoc """
  AC-10: extended migration coverage protecting the four outcomes the
  Migrations state machine can currently produce, plus the read-only
  contract Session enforces when a payload is newer than the server.

  Version 1 is the only released logical schema version, so the
  `@migrations` map inside `DigitalOilSticker.LocalStore.Migrations` is
  empty by design. AC-10 asks that "recorded fixtures of every prior
  version are covered by migration unit tests" — the fixture chain is
  empty at v1, so this file covers the machinery itself. When v2 lands,
  a v1→v2 step is registered and this file gains a real fixture-driven
  round-trip; the outcomes exercised here (same-version, newer-than-
  server, missing-step, read-only-on-newer) must continue to hold.

  The failure mode this guards: a future edit that "helpfully" makes a
  forward request with no registered step return `{:ok, data, :migrated}`
  (dropping unknown fields at the older version), or a Session hydrate
  path that quietly permits writes at a newer schema — either would
  silently corrupt a browser holding data from a later release, exactly
  what FR-10/FR-11 forbid.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.LocalStore.Migrations

  @data %{
    "meta" => %{"schema_version" => 1, "seq" => 4},
    "vehicles" => [%{"vehicle_id" => "1f2e3d4c-5b6a-4987-8abc-def012345678"}],
    "events" => [],
    "readings" => [],
    "usage" => [],
    "reminders" => [],
    "prefs" => nil
  }

  @v1_envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 2,
    "tab_id" => "tab-v1",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 2},
      "vehicles" => [
        %{
          "vehicle_id" => "22222222-2222-4222-8222-222222222222",
          "nickname" => "Wagon",
          "archived" => false
        }
      ],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  # A payload from a future release — same envelope shape, but a
  # schema_version the server has never heard of. Server must treat it
  # as read-only and never write it back at a downgraded version.
  @v2_envelope %{@v1_envelope | "schema_version" => 2, "tab_id" => "tab-v2"}

  describe "Migrations.migrate/3 machinery" do
    test "same version returns the data unchanged, never a re-write" do
      # Sanity for the current release: the only version we serve.
      assert Migrations.migrate(@data, 1, 1) == {:ok, @data, :unchanged}
      # And for any hypothetical future stable version.
      assert Migrations.migrate(@data, 5, 5) == {:ok, @data, :unchanged}
    end

    test "a payload newer than the server is a read-only signal, never a write" do
      # The version tag on the returned error is the CLIENT's version,
      # not the server's — the UI needs to be able to say what it is
      # refusing to touch.
      assert Migrations.migrate(@data, 2, 1) == {:error, {:newer_than_server, 2}}
      assert Migrations.migrate(@data, 9, 3) == {:error, {:newer_than_server, 9}}
    end

    test "a forward step with no registered migration fails naming the version" do
      # While `@migrations` is empty, the compile-time branch answers
      # every forward request with `{:error, {:migration_failed, from}}`
      # — behaviourally identical to the runtime `:missing_step` path
      # that will activate the moment the map gains a step but a caller
      # asks for a gap it does not cover.
      assert Migrations.migrate(@data, 1, 2) == {:error, {:migration_failed, 1}}
      assert Migrations.migrate(@data, 1, 5) == {:error, {:migration_failed, 1}}
    end
  end

  describe "Session hydrate at a newer schema version (FR-11)" do
    test "schema_version 1 hydrates loaded and mutable", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "local_store:hydrate", @v1_envelope)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.local_state == :loaded
      assert assigns.read_only == false
    end

    test "schema_version 2 payload locks the tab read-only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "local_store:hydrate", @v2_envelope)

      socket = :sys.get_state(view.pid).socket
      # FR-11 contract: state ends `:loaded` (the tab is usable to read
      # and export) but writes are hard-disabled — so mutations_enabled?
      # is false and the reason is read_only, not storage_mode or
      # local_state.
      assert socket.assigns.local_state == :loaded
      assert socket.assigns.read_only == true
      refute DigitalOilStickerWeb.LocalStore.Session.mutations_enabled?(socket)
    end
  end
end
