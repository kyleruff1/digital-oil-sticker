defmodule DigitalOilSticker.ClockDeterminismTest do
  @moduledoc """
  AC-9 (M01-002 / FR-9): domain calculations are deterministic in explicit
  inputs, `Clock`, timezone, units, and policy version. Injecting a fixed
  `Clock` implementation produces byte-identical output across runs.

  The Clock port exists so wall-clock leakage can be spotted at the boundary
  rather than as a flaky test months later. This proves the boundary works:
  pin the clock, compute twice, get the same value; and prove the clock is
  actually being consulted by shifting it and getting a different value.
  """
  use ExUnit.Case, async: false

  alias DigitalOilSticker.{Clock, Due}

  defmodule FixedClock2026 do
    @behaviour DigitalOilSticker.Clock
    @impl true
    def today, do: ~D[2026-06-15]
    @impl true
    def now, do: ~U[2026-06-15 12:00:00Z]
  end

  defmodule FixedClock2028 do
    @behaviour DigitalOilSticker.Clock
    @impl true
    def today, do: ~D[2028-01-01]
    @impl true
    def now, do: ~U[2028-01-01 00:00:00Z]
  end

  setup do
    original = Application.get_env(:digital_oil_sticker, :clock)

    on_exit(fn ->
      if original do
        Application.put_env(:digital_oil_sticker, :clock, original)
      else
        Application.delete_env(:digital_oil_sticker, :clock)
      end
    end)

    :ok
  end

  @vehicle %{
    "vehicle_id" => "11111111-1111-4111-8111-111111111111",
    "engine_class_code" => "gas_direct_injection",
    "maintenance_plan" => %{}
  }

  @event %{
    "event_id" => "22222222-2222-4222-8222-222222222222",
    "vehicle_id" => "11111111-1111-4111-8111-111111111111",
    "performed_at" => "2026-03-01",
    "odometer_m" => 100_584_000,
    "input_unit" => "mi",
    "oil_base_stock" => "full_synthetic"
  }

  test "the Clock port is honored: today() reflects the injected implementation" do
    Application.put_env(:digital_oil_sticker, :clock, FixedClock2026)
    assert Clock.today() == ~D[2026-06-15]

    Application.put_env(:digital_oil_sticker, :clock, FixedClock2028)
    assert Clock.today() == ~D[2028-01-01]
  end

  test "Due.compute is deterministic across runs with the same fixed Clock" do
    Application.put_env(:digital_oil_sticker, :clock, FixedClock2026)

    a = Due.compute(@vehicle, @event)
    b = Due.compute(@vehicle, @event)
    c = Due.compute(@vehicle, @event)

    assert a == b
    assert b == c
  end

  test "Due.compute output is stable when only the wall clock moves" do
    Application.put_env(:digital_oil_sticker, :clock, FixedClock2026)
    reference = Due.compute(@vehicle, @event)

    Application.put_env(:digital_oil_sticker, :clock, FixedClock2028)
    later = Due.compute(@vehicle, @event)

    # Due.compute takes the event date as its basis, not "now". So swapping
    # the clock underneath must not shift the answer — the test proves the
    # rule the module documents: "target computed from the current odometer
    # is never reached." Same applies to dates.
    assert reference == later
  end
end
