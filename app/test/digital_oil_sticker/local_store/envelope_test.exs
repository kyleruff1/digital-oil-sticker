defmodule DigitalOilSticker.LocalStore.EnvelopeTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.LocalStore.{Envelope, Validation}
  alias DigitalOilSticker.LocalStore.Schema.V1

  @vehicle_id "1f2e3d4c-5b6a-4987-8abc-def012345678"
  @event_id "aaaa1111-2222-4333-8444-555566667777"

  defp valid_vehicle do
    %{"vehicle_id" => @vehicle_id, "nickname" => "Truck", "archived" => false}
  end

  defp valid_envelope_map(overrides \\ %{}) do
    Map.merge(
      %{
        "envelope" => "dos_local",
        "schema_version" => 1,
        "seq" => 7,
        "tab_id" => "tab-abc123",
        "generated_at" => "2026-07-31T12:00:00Z",
        "data" => %{
          "meta" => %{"schema_version" => 1, "seq" => 7},
          "vehicles" => [valid_vehicle()],
          "events" => [],
          "readings" => [],
          "usage" => [],
          "reminders" => [],
          "prefs" => %{"unit_system" => "mi"}
        }
      },
      overrides
    )
  end

  describe "decode/1 with a valid envelope" do
    test "decodes every field onto the struct" do
      assert {:ok, %Envelope{} = env} = Envelope.decode(valid_envelope_map())
      assert env.schema_version == 1
      assert env.seq == 7
      assert env.tab_id == "tab-abc123"
      assert env.generated_at == "2026-07-31T12:00:00Z"
      assert env.data["vehicles"] == [valid_vehicle()]
      assert env.data["prefs"] == %{"unit_system" => "mi"}
      assert env.storage == nil
    end

    test "missing collections default to empty list / nil" do
      map = valid_envelope_map(%{"data" => %{"vehicles" => [valid_vehicle()]}})

      assert {:ok, env} = Envelope.decode(map)
      assert env.data["vehicles"] == [valid_vehicle()]
      assert env.data["events"] == []
      assert env.data["readings"] == []
      assert env.data["usage"] == []
      assert env.data["reminders"] == []
      assert env.data["meta"] == nil
      assert env.data["prefs"] == nil
    end
  end

  describe "decode/1 unknown top-level keys" do
    test "rejects an unknown top-level key naming the key" do
      map = Map.put(valid_envelope_map(), "surprise", true)
      assert Envelope.decode(map) == {:error, {:unknown_top_level_key, "surprise"}}
    end

    test "rejects each unknown top-level key by its own name" do
      for key <- ["extra", "payload", "user_id", "checksum"] do
        map = Map.put(valid_envelope_map(), key, "x")
        assert Envelope.decode(map) == {:error, {:unknown_top_level_key, key}}
      end
    end

    test "rejects an unknown collection name inside data" do
      data = Map.put(valid_envelope_map()["data"], "forecasts", [])
      map = valid_envelope_map(%{"data" => data})
      assert Envelope.decode(map) == {:error, {:unknown_top_level_key, "forecasts"}}
    end
  end

  describe "decode/1 envelope shape errors" do
    test "non-map input is not an envelope" do
      assert Envelope.decode("nope") == {:error, :not_an_envelope}
      assert Envelope.decode(nil) == {:error, :not_an_envelope}
      assert Envelope.decode([1, 2]) == {:error, :not_an_envelope}
    end

    test "wrong or missing envelope marker is not an envelope" do
      assert Envelope.decode(Map.put(valid_envelope_map(), "envelope", "dos_other")) ==
               {:error, :not_an_envelope}

      assert Envelope.decode(Map.delete(valid_envelope_map(), "envelope")) ==
               {:error, :not_an_envelope}
    end

    test "bad schema_version yields :bad_version" do
      assert Envelope.decode(Map.put(valid_envelope_map(), "schema_version", 0)) ==
               {:error, :bad_version}

      assert Envelope.decode(Map.put(valid_envelope_map(), "schema_version", "1")) ==
               {:error, :bad_version}

      assert Envelope.decode(Map.delete(valid_envelope_map(), "schema_version")) ==
               {:error, :bad_version}
    end

    test "missing required fields are not an envelope" do
      for key <- ["seq", "tab_id", "generated_at", "data"] do
        assert Envelope.decode(Map.delete(valid_envelope_map(), key)) ==
                 {:error, :not_an_envelope}
      end
    end

    test "wrongly typed required fields are not an envelope" do
      assert Envelope.decode(Map.put(valid_envelope_map(), "seq", -1)) ==
               {:error, :not_an_envelope}

      assert Envelope.decode(Map.put(valid_envelope_map(), "tab_id", 5)) ==
               {:error, :not_an_envelope}

      assert Envelope.decode(Map.put(valid_envelope_map(), "data", "not a map")) ==
               {:error, :not_an_envelope}
    end
  end

  describe "storage sibling" do
    test "is optional and carried on the struct when present" do
      map = Map.put(valid_envelope_map(), "storage", %{"persisted" => true, "quota" => 12345})
      assert {:ok, env} = Envelope.decode(map)
      assert env.storage == %{"persisted" => true, "quota" => 12345}
    end

    test "must be a map when present" do
      map = Map.put(valid_envelope_map(), "storage", "yes")
      assert Envelope.decode(map) == {:error, :not_an_envelope}
    end
  end

  describe "unknown keys inside a record (AC-9)" do
    test "survive decode -> validate -> write-back byte-for-byte in __unknown__" do
      future_payload = %{"nested" => %{"deep" => [1, 2, 3]}, "flag" => "é-bytes"}

      event =
        %{
          "event_id" => @event_id,
          "vehicle_id" => @vehicle_id,
          "performed_at" => "2026-07-01T09:30:00Z",
          "odometer_m" => 120_000_000,
          "input_unit" => "mi",
          "provenance_mode" => "manual"
        }
        |> Map.put("from_the_future", future_payload)
        |> Map.put("another_new_field", "kept verbatim")

      data = Map.merge(valid_envelope_map()["data"], %{"events" => [event]})
      map = valid_envelope_map(%{"data" => data})

      assert {:ok, envelope} = Envelope.decode(map)
      assert {:ok, %{data: canonical, quarantine: []}} = Validation.validate(envelope, 1_000)

      assert [canonical_event] = canonical["events"]

      assert canonical_event["__unknown__"] == %{
               "from_the_future" => future_payload,
               "another_new_field" => "kept verbatim"
             }

      # Simulated write-back: restoring the canonical record reproduces the
      # original record exactly, unknown keys flat and byte-for-byte.
      assert V1.restore_unknown(canonical_event) == event
    end
  end

  describe "build_put/4" do
    test "builds the put instruction shape" do
      upserts = [{"events", %{"event_id" => @event_id}}]
      deletes = [{"readings", "some-key"}]

      assert Envelope.build_put("mut-1", 8, upserts, deletes) == %{
               "mutation_id" => "mut-1",
               "seq" => 8,
               "upserts" => [%{"store" => "events", "record" => %{"event_id" => @event_id}}],
               "deletes" => [%{"store" => "readings", "key" => "some-key"}]
             }
    end
  end

  test "current_schema_version/0" do
    assert Envelope.current_schema_version() == 1
  end
end
