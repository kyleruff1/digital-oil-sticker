defmodule DigitalOilSticker.LocalStore.Caps do
  @moduledoc """
  Hard caps on the hydrate payload (DOS-M09-001 FR-14, DOS-M09-002 FR-7).

  Caps are enforced server-side and rejected explicitly with the specific
  cap named. Silent truncation is prohibited: a payload over a cap yields an
  error naming which cap, never a trimmed subset.

    * decoded payload size — 1 MiB (1,048,576 bytes)
    * vehicles — 200
    * events — 5,000
    * readings — 20,000
  """

  alias DigitalOilSticker.LocalStore.Envelope

  @max_payload_bytes 1_048_576
  @max_vehicles 200
  @max_events 5_000
  @max_readings 20_000

  @type cap :: :payload_bytes | :vehicles | :events | :readings

  @spec max_payload_bytes() :: pos_integer()
  def max_payload_bytes, do: @max_payload_bytes

  @spec max_vehicles() :: pos_integer()
  def max_vehicles, do: @max_vehicles

  @spec max_events() :: pos_integer()
  def max_events, do: @max_events

  @spec max_readings() :: pos_integer()
  def max_readings, do: @max_readings

  @doc """
  Checks a decoded envelope against every hard cap.

  `byte_size` is the size in bytes of the decoded payload as received.
  Returns `:ok` when every cap holds (a count exactly at a cap passes), or
  `{:error, {:cap_exceeded, cap}}` naming the first exceeded cap.
  """
  @spec check(Envelope.t(), non_neg_integer()) :: :ok | {:error, {:cap_exceeded, cap()}}
  def check(%Envelope{data: data}, byte_size) when is_integer(byte_size) and byte_size >= 0 do
    cond do
      byte_size > @max_payload_bytes -> {:error, {:cap_exceeded, :payload_bytes}}
      count(data, "vehicles") > @max_vehicles -> {:error, {:cap_exceeded, :vehicles}}
      count(data, "events") > @max_events -> {:error, {:cap_exceeded, :events}}
      count(data, "readings") > @max_readings -> {:error, {:cap_exceeded, :readings}}
      true -> :ok
    end
  end

  defp count(data, collection) do
    case Map.get(data, collection) do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end
end
