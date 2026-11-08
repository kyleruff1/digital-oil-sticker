defmodule DigitalOilSticker.Sticker do
  @moduledoc """
  The API-side shape of a sticker: how a POS/DMS caller builds one, and how
  that shape turns into the canonical scanner URL.

  `StickerCode` already defines the wire format and the field vocabulary
  (`configuration_key`, `changed_on`, `odometer_m`, `grade`, `base_stock`).
  This module is the thin adapter between those fields and the two things the
  integration surface needs:

    * normalize params coming in from JSON — where every key is a string, every
      value may be a string, and odometer may be miles-with-a-unit — into the
      atom-keyed, canonical-unit sticker map `StickerCode.encode/1` reads,
    * build the canonical scanner URL (`https://<host>/s#<code>`) that the QR
      encodes.

  Zero validator code lives here. `StickerCode.encode/1` is the validator: a
  value is valid iff it encodes, and the error atom it returns names the
  field. Duplicating that logic is how the two slowly drift apart.

  Domain-only — no Phoenix, no Plug, no Hosts. The caller (web controller or
  MCP tool) decides which host to put in the URL.
  """

  alias DigitalOilSticker.{StickerCode, Units}

  @type params :: %{optional(String.t()) => term()}

  @doc """
  Parse JSON-shaped params into the sticker map `StickerCode.encode/1` accepts.

  Accepts string keys (how JSON arrives) and the two odometer conveniences a
  POS integrator will reach for first: `odometer_m` as integer metres
  (canonical), or `odometer` with a separate `odometer_unit` of "mi" or "km".
  Dates may be ISO 8601 strings or `%Date{}`. Everything else is passed
  through for `encode/1` to accept or reject.
  """
  @spec from_params(params()) :: {:ok, StickerCode.sticker()} | {:error, atom()}
  def from_params(params) when is_map(params) do
    with {:ok, changed_on} <- parse_date(Map.get(params, "changed_on")),
         {:ok, odometer_m} <- parse_odometer(params) do
      {:ok,
       StickerCode.normalize(%{
         configuration_key: Map.get(params, "configuration_key"),
         changed_on: changed_on,
         odometer_m: odometer_m,
         grade: Map.get(params, "grade"),
         base_stock: Map.get(params, "base_stock")
       })}
    end
  end

  def from_params(_), do: {:error, :invalid_params}

  @doc """
  The URL a scanner opens. The code is in the URL FRAGMENT (`#`), not the path
  or a query string: fragments never travel to the server, so a shop's QR
  scan never shares the vehicle values with our logs or any intermediary.
  This mirrors how the live LiveView at `/s` already works.
  """
  @spec canonical_url(String.t(), String.t()) :: String.t()
  def canonical_url(code, host) when is_binary(code) and is_binary(host) do
    "https://" <> host <> "/s#" <> code
  end

  # -- param parsers -----------------------------------------------------------

  defp parse_date(nil), do: {:ok, nil}
  defp parse_date(%Date{} = d), do: {:ok, d}

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :invalid_date}
    end
  end

  defp parse_date(_), do: {:error, :invalid_date}

  # odometer_m (integer metres) wins when given — it's the canonical form.
  # Otherwise accept a {value, unit} pair and convert.
  defp parse_odometer(params) do
    case Map.get(params, "odometer_m") do
      nil ->
        parse_odometer_pair(Map.get(params, "odometer"), Map.get(params, "odometer_unit"))

      m when is_integer(m) and m >= 0 ->
        {:ok, m}

      _ ->
        {:error, :odometer_out_of_range}
    end
  end

  defp parse_odometer_pair(nil, _), do: {:ok, nil}

  defp parse_odometer_pair(value, "m") when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_odometer_pair(value, "mi"), do: convert_to_metres(value, :mi)
  defp parse_odometer_pair(value, "km"), do: convert_to_metres(value, :km)
  defp parse_odometer_pair(_, _), do: {:error, :odometer_out_of_range}

  defp convert_to_metres(value, unit) do
    case Units.to_metres(value, unit) do
      {:ok, metres} -> {:ok, metres}
      {:error, _} -> {:error, :odometer_out_of_range}
    end
  end
end
