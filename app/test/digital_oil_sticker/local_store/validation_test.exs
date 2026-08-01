defmodule DigitalOilSticker.LocalStore.ValidationTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.LocalStore.{Envelope, Quarantine, Validation}

  @vehicle_id "1f2e3d4c-5b6a-4987-8abc-def012345678"
  @other_vehicle_id "0a1b2c3d-4e5f-4678-9abc-0123456789ab"
  @event_id "aaaa1111-2222-4333-8444-555566667777"
  @bad_event_id "bbbb1111-2222-4333-8444-555566667777"
  @reading_id "cccc1111-2222-4333-8444-555566667777"
  @usage_id "dddd1111-2222-4333-8444-555566667777"
  @reminder_id "eeee1111-2222-4333-8444-555566667777"

  defp vehicle(id \\ @vehicle_id) do
    %{"vehicle_id" => id, "nickname" => "Truck", "archived" => false}
  end

  defp event(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => @event_id,
        "vehicle_id" => @vehicle_id,
        "performed_at" => "2026-07-01T09:30:00Z",
        "odometer_m" => 120_000_000,
        "input_unit" => "mi",
        "provenance_mode" => "catalog"
      },
      overrides
    )
  end

  defp reading(overrides \\ %{}) do
    Map.merge(
      %{
        "reading_id" => @reading_id,
        "vehicle_id" => @vehicle_id,
        "observed_at" => "2026-07-15T08:00:00Z",
        "odometer_m" => 121_000_000,
        "input_unit" => "mi"
      },
      overrides
    )
  end

  defp envelope(data_overrides) do
    data =
      Map.merge(
        %{
          "meta" => %{"schema_version" => 1, "seq" => 3},
          "prefs" => %{"unit_system" => "mi"},
          "vehicles" => [vehicle()],
          "events" => [],
          "readings" => [],
          "usage" => [],
          "reminders" => []
        },
        data_overrides
      )

    %Envelope{
      schema_version: 1,
      seq: 3,
      tab_id: "tab",
      generated_at: "2026-07-31T00:00:00Z",
      data: data
    }
  end

  defp validate(env), do: Validation.validate(env, 1_000)

  test "a fully valid envelope hydrates with an empty quarantine" do
    env = envelope(%{"events" => [event()], "readings" => [reading()]})

    assert {:ok, %{data: data, quarantine: []}} = validate(env)
    assert [%{"vehicle_id" => @vehicle_id}] = data["vehicles"]
    assert [%{"event_id" => @event_id}] = data["events"]
    assert [%{"reading_id" => @reading_id}] = data["readings"]
    assert data["meta"]["seq"] == 3
    assert data["prefs"]["unit_system"] == "mi"
  end

  test "caps are checked first" do
    env = envelope(%{"events" => [event()]})

    assert Validation.validate(env, 1_048_577) == {:error, {:cap_exceeded, :payload_bytes}}
  end

  describe "per-rule quarantine, valid remainder hydrates" do
    test "bad uuid quarantines with :invalid_uuid" do
      env = envelope(%{"vehicles" => [vehicle(), vehicle("not-a-uuid")]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "vehicles", id: "not-a-uuid", rule: :invalid_uuid} = entry
      assert [%{"vehicle_id" => @vehicle_id}] = data["vehicles"]
    end

    test "non-v4 uuid quarantines with :invalid_uuid" do
      # valid shape but version 1 in the third group
      v1_uuid = "aaaa1111-2222-1333-8444-555566667777"
      env = envelope(%{"vehicles" => [vehicle(), vehicle(v1_uuid)]})

      assert {:ok, %{quarantine: [%Quarantine{rule: :invalid_uuid, id: ^v1_uuid}]}} =
               validate(env)
    end

    test "negative odometer quarantines with :invalid_odometer" do
      bad = event(%{"event_id" => @bad_event_id, "odometer_m" => -5})
      env = envelope(%{"events" => [event(), bad]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "events", id: @bad_event_id, rule: :invalid_odometer} = entry
      assert [%{"event_id" => @event_id}] = data["events"]
    end

    test "non-integer odometer quarantines with :invalid_odometer" do
      bad = reading(%{"odometer_m" => "121000"})
      env = envelope(%{"readings" => [bad]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "readings", id: @reading_id, rule: :invalid_odometer} = entry
      assert data["readings"] == []
    end

    test "bad unit quarantines with :invalid_unit" do
      bad = reading(%{"input_unit" => "furlongs"})
      env = envelope(%{"readings" => [reading(%{"reading_id" => @usage_id}), bad]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "readings", id: @reading_id, rule: :invalid_unit} = entry
      assert length(data["readings"]) == 1
    end

    test "bad provenance_mode quarantines with :invalid_provenance_mode" do
      bad = event(%{"event_id" => @bad_event_id, "provenance_mode" => "guessed"})
      env = envelope(%{"events" => [event(), bad]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)

      assert %Quarantine{store: "events", id: @bad_event_id, rule: :invalid_provenance_mode} =
               entry

      assert [%{"event_id" => @event_id}] = data["events"]
    end

    test "unparseable date quarantines with :unparseable_instant" do
      bad = event(%{"event_id" => @bad_event_id, "performed_at" => "last Tuesday"})
      env = envelope(%{"events" => [event(), bad]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "events", id: @bad_event_id, rule: :unparseable_instant} = entry
      assert [%{"event_id" => @event_id}] = data["events"]
    end

    test "a date-only ISO8601 value parses" do
      env =
        envelope(%{
          "usage" => [
            %{
              "usage_id" => @usage_id,
              "vehicle_id" => @vehicle_id,
              "effective_from" => "2026-07-01"
            }
          ]
        })

      assert {:ok, %{quarantine: []}} = validate(env)
    end

    test "orphan vehicle_id quarantines with :orphan_vehicle_id across all scoped stores" do
      env =
        envelope(%{
          "events" => [event(%{"vehicle_id" => @other_vehicle_id})],
          "readings" => [reading()],
          "usage" => [
            %{
              "usage_id" => @usage_id,
              "vehicle_id" => @other_vehicle_id,
              "effective_from" => "2026-07-01"
            }
          ],
          "reminders" => [
            %{"reminder_id" => @reminder_id, "vehicle_id" => @other_vehicle_id, "enabled" => true}
          ]
        })

      assert {:ok, %{data: data, quarantine: quarantine}} = validate(env)

      rules_by_store = Enum.map(quarantine, &{&1.store, &1.rule})

      assert {"events", :orphan_vehicle_id} in rules_by_store
      assert {"usage", :orphan_vehicle_id} in rules_by_store
      assert {"reminders", :orphan_vehicle_id} in rules_by_store
      assert length(quarantine) == 3

      # the correctly linked reading still hydrates
      assert [%{"reading_id" => @reading_id}] = data["readings"]
      assert data["events"] == []
      assert data["usage"] == []
      assert data["reminders"] == []
    end

    test "non-map record quarantines with :not_a_map" do
      env = envelope(%{"events" => [event(), "corrupted string"]})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "events", id: nil, rule: :not_a_map} = entry
      assert [%{"event_id" => @event_id}] = data["events"]
    end

    test "non-map meta singleton quarantines and the rest hydrates" do
      env = envelope(%{"meta" => "corrupt"})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "meta", id: "meta", rule: :not_a_map} = entry
      assert data["meta"] == nil
      assert [%{"vehicle_id" => @vehicle_id}] = data["vehicles"]
    end

    test "bad prefs unit_system quarantines the prefs singleton" do
      env = envelope(%{"prefs" => %{"unit_system" => "leagues"}})

      assert {:ok, %{data: data, quarantine: [entry]}} = validate(env)
      assert %Quarantine{store: "prefs", id: "prefs", rule: :invalid_unit} = entry
      assert data["prefs"] == nil
    end

    test "absent meta and prefs are nil with no quarantine" do
      env = envelope(%{"meta" => nil, "prefs" => nil})

      assert {:ok, %{data: data, quarantine: []}} = validate(env)
      assert data["meta"] == nil
      assert data["prefs"] == nil
    end
  end

  test "quarantine entries never carry record contents and inspect cleanly" do
    bad = event(%{"event_id" => @bad_event_id, "odometer_m" => -5, "notes" => "SECRET NOTE"})
    env = envelope(%{"events" => [bad]})

    assert {:ok, %{quarantine: [entry]}} = validate(env)
    rendered = inspect(entry)
    refute rendered =~ "SECRET NOTE"
    assert rendered =~ ":invalid_odometer"
  end
end
