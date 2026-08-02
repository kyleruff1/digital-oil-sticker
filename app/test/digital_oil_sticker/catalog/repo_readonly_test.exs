defmodule DigitalOilSticker.Catalog.RepoReadonlyTest do
  @moduledoc """
  The DOS-M09-004 FR-16 / DOS-M09-002 AC-1 release gate: the deployed repo
  list is exactly [CatalogRepo], opened read-only, with PRAGMA query_only ON,
  and no write can reach the file through any layer.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.CatalogRepo

  test "the configured repo list is exactly [CatalogRepo]" do
    assert Application.fetch_env!(:digital_oil_sticker, :ecto_repos) == [CatalogRepo]
  end

  test "no other Ecto repo runs under the app supervisor" do
    repos =
      DigitalOilSticker.Supervisor
      |> Supervisor.which_children()
      |> Enum.map(fn {id, _pid, _type, _mods} -> id end)
      |> Enum.filter(&(is_atom(&1) and function_exported?(&1, :__adapter__, 0)))

    assert repos == [CatalogRepo]
  end

  test "read_only: true removed the write API at compile time" do
    for {fun, arity} <- [
          insert: 2,
          update: 2,
          delete: 2,
          insert_all: 3,
          update_all: 3,
          delete_all: 2
        ] do
      refute function_exported?(CatalogRepo, fun, arity),
             "#{fun}/#{arity} must not exist on a read-only repo"
    end
  end

  test "PRAGMA query_only is ON for pooled connections" do
    assert %{rows: [[1]]} = Ecto.Adapters.SQL.query!(CatalogRepo, "PRAGMA query_only", [])
  end

  test "the artifact is not in WAL mode (read-only image opens need DELETE)" do
    assert %{rows: [["delete"]]} =
             Ecto.Adapters.SQL.query!(CatalogRepo, "PRAGMA journal_mode", [])
  end

  test "mutations are rejected at the connection layer" do
    for stmt <- [
          "INSERT INTO makes (id, display_name, normalized_name, support_status, source_id) VALUES ('x','X','x','identity_only','s')",
          "UPDATE makes SET display_name = 'X'",
          "DELETE FROM makes",
          "CREATE TABLE t (a TEXT)",
          "DROP TABLE makes",
          "PRAGMA user_version = 7",
          "VACUUM"
        ] do
      assert {:error, _} = Ecto.Adapters.SQL.query(CatalogRepo, stmt, []),
             "statement must be rejected: #{stmt}"
    end
  end

  test "query_only cannot be switched off by a session" do
    # All three statements must run on ONE connection. The pragma is
    # per-connection and Ecto hands out an arbitrary pooled connection per
    # query, so without a checkout the OFF and the restoring ON can land on
    # different connections — leaving one poisoned for whichever test picks it
    # up next. That is not hypothetical: it broke the readiness check when it
    # was added, and then broke this test.
    CatalogRepo.checkout(fn ->
      _ = Ecto.Adapters.SQL.query(CatalogRepo, "PRAGMA query_only = OFF", [])

      # mode: :readonly is an independent layer below query_only, so the write
      # must still be refused even with the pragma off.
      assert {:error, _} = Ecto.Adapters.SQL.query(CatalogRepo, "DELETE FROM makes", [])

      _ = Ecto.Adapters.SQL.query(CatalogRepo, "PRAGMA query_only = ON", [])
    end)
  end

  test "the catalog fixture is present, queryable, and honestly empty where unlicensed" do
    assert %{rows: [[n]]} =
             Ecto.Adapters.SQL.query!(CatalogRepo, "SELECT count(*) FROM makes", [])

    assert n > 0

    assert %{rows: [[0]]} =
             Ecto.Adapters.SQL.query!(
               CatalogRepo,
               "SELECT count(*) FROM maintenance_schedules",
               []
             )

    assert %{rows: [[0]]} =
             Ecto.Adapters.SQL.query!(CatalogRepo, "SELECT count(*) FROM oil_requirements", [])
  end

  test "no -wal or -shm sidecar exists beside the fixture" do
    db = Application.get_env(:digital_oil_sticker, CatalogRepo)[:database]
    refute File.exists?(db <> "-wal")
    refute File.exists?(db <> "-shm")
  end
end
