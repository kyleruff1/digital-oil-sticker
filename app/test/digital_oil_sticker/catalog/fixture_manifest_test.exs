defmodule DigitalOilSticker.Catalog.FixtureManifestTest do
  @moduledoc """
  M01-004 AC-2 and AC-8: repeated fixture builds must match the deterministic
  hash + row-count contract, and fixture inputs must be immutable.

  The manifest at `app/priv/catalog/catalog-fixture-manifest.json` is the
  contract. This test asserts the committed fixture-a and fixture-b files
  still satisfy it — a manual edit to either the artifact or the manifest
  fails here immediately. Real double-build verification (re-run the pipeline
  and diff the SHA) belongs to CI and lives in `M01-006` as a required gate;
  this test guards the invariant that the committed pair is the pair the
  manifest describes.
  """
  use ExUnit.Case, async: true

  @app_root Path.expand("../../..", __DIR__)
  @catalog_dir Path.join(@app_root, "priv/catalog")

  defp sha256_hex(path) do
    :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
  end

  defp row_count(db_path, table) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path, mode: :readonly)

    try do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM #{table}")

      count =
        case Exqlite.Sqlite3.step(conn, stmt) do
          {:row, [n]} -> n
        end

      Exqlite.Sqlite3.release(conn, stmt)
      count
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  setup_all do
    manifest_path = Path.join(@catalog_dir, "catalog-fixture-manifest.json")
    manifest = manifest_path |> File.read!() |> :json.decode()
    {:ok, manifest: manifest}
  end

  test "manifest names both fixture artifacts", %{manifest: manifest} do
    artifacts = Map.keys(manifest["artifacts"])
    assert "catalog.sqlite3" in artifacts
    assert "catalog-fixture-b.sqlite3" in artifacts
  end

  test "fixture-a SHA256 matches the manifest", %{manifest: manifest} do
    expected = manifest["artifacts"]["catalog.sqlite3"]["sha256"]
    actual = sha256_hex(Path.join(@catalog_dir, "catalog-fixture-a.sqlite3"))
    assert actual == expected
  end

  test "fixture-b SHA256 matches the manifest", %{manifest: manifest} do
    expected = manifest["artifacts"]["catalog-fixture-b.sqlite3"]["sha256"]
    actual = sha256_hex(Path.join(@catalog_dir, "catalog-fixture-b.sqlite3"))
    assert actual == expected
  end

  test "fixture-a row counts match the manifest", %{manifest: manifest} do
    fixture_path = Path.join(@catalog_dir, "catalog-fixture-a.sqlite3")
    expected = manifest["artifacts"]["catalog.sqlite3"]["counts"]

    for {table, expected_count} <- expected do
      assert row_count(fixture_path, table) == expected_count,
             "fixture-a #{table} row count differs from manifest"
    end
  end

  test "fixture-b differs from fixture-a in exactly one configuration removal",
       %{manifest: manifest} do
    # `removed_in_b` is the configuration_key that fixture-b removes. Its
    # presence lets migration/reader tests exercise a real "row goes away
    # between data_versions" scenario without hand-crafting a diff.
    removed = manifest["removed_in_b"]
    assert is_binary(removed)
    assert byte_size(removed) == 36

    a_count = manifest["artifacts"]["catalog.sqlite3"]["counts"]["vehicle_configurations"]

    b_count =
      manifest["artifacts"]["catalog-fixture-b.sqlite3"]["counts"]["vehicle_configurations"]

    assert b_count == a_count - 1
  end
end
