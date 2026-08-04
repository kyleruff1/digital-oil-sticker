defmodule DigitalOilStickerWeb.LocalStore.UnknownKeyRoundtripTest do
  @moduledoc """
  DOS-M09-002 AC-9 / FR-10: an unknown top-level key on a hydrated record
  survives the hydrate → mutate → write-back path byte-for-byte.

  This is the forward-compatibility contract Schema.V1's `__unknown__`
  carry-through exists to provide. A newer deployment writes a field an
  older deployment does not recognize; the older deployment reads that
  record, canonicalizes the field into `__unknown__`, and any later write
  of the same record must restore the field flat at the wire boundary.
  If restore_unknown/1 is skipped at the mutation choke point, the field
  is persisted permanently nested under `__unknown__`, and the newer
  deployment's flat read is silently shadowed — the exact silent data
  loss FR-10 promises to prevent.

  The mutation choke point is `Session.stage_mutation/3`, which calls
  `restore_record/1 → Schema.V1.restore_unknown/1` before building the
  `local_store:put` payload. This test drives a real UI event
  (`set_condition`, on the vehicle profile page) that upserts the same
  vehicle we hydrated, then inspects the emitted `local_store:put`
  payload to confirm the sentinel unknown key rides through flat and
  unchanged.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @sentinel_key "future_field_xyz"
  @sentinel_value "sentinel-value-12345"
  @vehicle_id "11111111-1111-4111-8111-111111111111"

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 1,
    "tab_id" => "t",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => nil,
      "vehicles" => [
        %{
          "vehicle_id" => @vehicle_id,
          "nickname" => "Truck",
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{
            "year" => 2020,
            "make" => "Toyota",
            "model" => "Camry",
            "build" => "LE"
          },
          "support_status" => "identity_only",
          "engine_class_code" => "gas_direct_injection",
          "maintenance_plan" => nil,
          # The whole point: a top-level key this release does not know
          # about, which must survive to the next write-back untouched.
          @sentinel_key => @sentinel_value
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

  test "unknown top-level record key survives hydrate → mutate → write-back byte-equal",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vehicle")
    render_hook(view, "local_store:hydrate", @envelope)

    # Confirm the vehicle actually hydrated into assigns.garage before we
    # rely on it being mutated. If this assertion fails, the test below is
    # meaningless — the mutation would be operating on an empty garage and
    # the unknown-key survival check would pass vacuously.
    garage = :sys.get_state(view.pid).socket.assigns.garage
    assert [hydrated] = garage.vehicles
    assert hydrated["vehicle_id"] == @vehicle_id

    # Post-canonicalization the sentinel lives under "__unknown__", not
    # flat. This is the state a mutation choke point without
    # restore_unknown/1 would persist verbatim — the failure mode this
    # test guards.
    assert hydrated["__unknown__"] == %{@sentinel_key => @sentinel_value}
    refute Map.has_key?(hydrated, @sentinel_key)

    # Drive a real staged mutation on the same vehicle. `set_condition`
    # merges `service_condition` into `maintenance_plan` and calls
    # `Session.stage_mutation/3` — the same choke point every save on
    # every page passes through.
    render_click(view, "set_condition", %{"condition" => "severe"})
    assert_push_event(view, "local_store:put", payload)

    assert [%{"store" => "vehicles", "record" => upserted}] = payload["upserts"]
    assert upserted["vehicle_id"] == @vehicle_id

    # The invariant. The sentinel is flat on the wire, byte-for-byte, and
    # the "__unknown__" wrapper is gone — a newer deployment reading this
    # record back will see the field it wrote, not a nested shadow.
    assert Map.get(upserted, @sentinel_key) == @sentinel_value
    refute Map.has_key?(upserted, "__unknown__")
  end
end
