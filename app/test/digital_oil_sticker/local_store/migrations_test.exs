defmodule DigitalOilSticker.LocalStore.MigrationsTest do
  use ExUnit.Case, async: true

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

  test "same version returns the data unchanged" do
    assert Migrations.migrate(@data, 1, 1) == {:ok, @data, :unchanged}
    assert Migrations.migrate(@data, 3, 3) == {:ok, @data, :unchanged}
  end

  test "a payload newer than the server is a read-only signal, never a write" do
    assert Migrations.migrate(@data, 2, 1) == {:error, {:newer_than_server, 2}}
    assert Migrations.migrate(@data, 9, 3) == {:error, {:newer_than_server, 9}}
  end

  test "a forward step with no registered migration fails naming the version" do
    # No migrations are registered while version 1 is the only released
    # version, so any forward request fails explicitly rather than skipping.
    assert Migrations.migrate(@data, 1, 2) == {:error, {:migration_failed, 1}}
  end
end
