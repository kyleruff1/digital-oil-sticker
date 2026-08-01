defmodule DigitalOilSticker.LocalStore.CapsTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.LocalStore.{Caps, Envelope}

  defp envelope(data_overrides \\ %{}) do
    data =
      Map.merge(
        %{
          "meta" => nil,
          "prefs" => nil,
          "vehicles" => [],
          "events" => [],
          "readings" => [],
          "usage" => [],
          "reminders" => []
        },
        data_overrides
      )

    %Envelope{
      schema_version: 1,
      seq: 0,
      tab_id: "tab",
      generated_at: "2026-07-31T00:00:00Z",
      data: data
    }
  end

  defp records(n), do: List.duplicate(%{}, n)

  describe "payload byte cap (1_048_576)" do
    test "passes exactly at the boundary" do
      assert Caps.check(envelope(), 1_048_576) == :ok
    end

    test "rejects boundary + 1 naming :payload_bytes" do
      assert Caps.check(envelope(), 1_048_577) == {:error, {:cap_exceeded, :payload_bytes}}
    end
  end

  describe "vehicle cap (200)" do
    test "passes exactly at the boundary" do
      assert Caps.check(envelope(%{"vehicles" => records(200)}), 0) == :ok
    end

    test "rejects boundary + 1 naming :vehicles" do
      assert Caps.check(envelope(%{"vehicles" => records(201)}), 0) ==
               {:error, {:cap_exceeded, :vehicles}}
    end
  end

  describe "event cap (5_000)" do
    test "passes exactly at the boundary" do
      assert Caps.check(envelope(%{"events" => records(5_000)}), 0) == :ok
    end

    test "rejects boundary + 1 naming :events" do
      assert Caps.check(envelope(%{"events" => records(5_001)}), 0) ==
               {:error, {:cap_exceeded, :events}}
    end
  end

  describe "reading cap (20_000)" do
    test "passes exactly at the boundary" do
      assert Caps.check(envelope(%{"readings" => records(20_000)}), 0) == :ok
    end

    test "rejects boundary + 1 naming :readings" do
      assert Caps.check(envelope(%{"readings" => records(20_001)}), 0) ==
               {:error, {:cap_exceeded, :readings}}
    end
  end

  test "all caps at their boundaries together pass" do
    env =
      envelope(%{
        "vehicles" => records(200),
        "events" => records(5_000),
        "readings" => records(20_000)
      })

    assert Caps.check(env, 1_048_576) == :ok
  end
end
