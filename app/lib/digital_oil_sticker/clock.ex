defmodule DigitalOilSticker.Clock do
  @moduledoc """
  Time source behaviour with a runtime-configurable implementation, so tests
  can inject a fixed clock:

      Application.put_env(:digital_oil_sticker, :clock, MyFixedClock)

  Defaults to `DigitalOilSticker.Clock.System` (UTC).
  """

  @callback today() :: Date.t()
  @callback now() :: DateTime.t()

  @spec today() :: Date.t()
  def today, do: impl().today()

  @spec now() :: DateTime.t()
  def now, do: impl().now()

  defp impl do
    Application.get_env(:digital_oil_sticker, :clock, DigitalOilSticker.Clock.System)
  end
end

defmodule DigitalOilSticker.Clock.System do
  @moduledoc "Default `DigitalOilSticker.Clock` implementation: real UTC time."

  @behaviour DigitalOilSticker.Clock

  @impl true
  def today, do: Date.utc_today()

  @impl true
  def now, do: DateTime.utc_now()
end
