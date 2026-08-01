defmodule DigitalOilSticker.Catalog.RateLimit do
  @moduledoc """
  Tier-1 rate limiting: a PURE token bucket held in the caller's own socket
  assigns. No shared table, no key, no state outliving one connection —
  therefore nothing to correlate and nothing to log (INV-26 by construction).
  Thresholds are recorded starting points to be measured (30 burst / 5 per
  second refill), not asserted constants.
  """

  defstruct capacity: 30, refill_per_second: 5, tokens: 30.0, updated_ms: 0

  @type t :: %__MODULE__{}

  @spec new(pos_integer(), pos_integer(), integer()) :: t()
  def new(capacity \\ 30, refill_per_second \\ 5, now_ms \\ 0) do
    %__MODULE__{
      capacity: capacity,
      refill_per_second: refill_per_second,
      tokens: capacity * 1.0,
      updated_ms: now_ms
    }
  end

  @spec take(t(), pos_integer(), integer()) :: {:ok, t()} | {:error, :rate_limited}
  def take(%__MODULE__{} = bucket, tokens \\ 1, now_ms) do
    elapsed_s = max(now_ms - bucket.updated_ms, 0) / 1000
    available = min(bucket.tokens + elapsed_s * bucket.refill_per_second, bucket.capacity * 1.0)

    if available >= tokens do
      {:ok, %{bucket | tokens: available - tokens, updated_ms: now_ms}}
    else
      {:error, :rate_limited}
    end
  end
end
