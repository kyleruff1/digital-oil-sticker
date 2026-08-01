defmodule DigitalOilSticker.Catalog.Cursor do
  @moduledoc """
  Opaque keyset cursors (DOS-M09-004 FR-11/AC-8): JSON array
  `[v, data_version, query_fingerprint | key_components]`, Base64url without
  padding. Components derive ONLY from catalog values already returned to the
  caller. data_version mismatch → :stale_cursor (checked FIRST); fingerprint
  mismatch or any malformation → :invalid_selector, no query executed. Not
  signed: the payload holds nothing secret and post-decode validation is the
  property that matters (owner decision D5).
  """
  alias DigitalOilSticker.Catalog.{Metadata, Selector}

  @version 1
  @fp_bytes 12

  @spec encode([binary() | integer()], Selector.t()) :: binary()
  def encode(key_components, %Selector{} = sel) do
    [@version, Metadata.data_version(), fingerprint(sel) | key_components]
    |> JSON.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(binary(), Selector.t()) ::
          {:ok, [term()]} | {:error, :stale_cursor | :invalid_selector}
  def decode(cursor, %Selector{} = sel) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, [@version, data_version, fp | components]} <- safe_json(json) do
      cond do
        # Structural validity first: a malformed cursor is malformed regardless
        # of which catalog version minted it.
        not valid_components?(components) -> {:error, :invalid_selector}
        data_version != Metadata.data_version() -> {:error, :stale_cursor}
        fp != fingerprint(sel) -> {:error, :invalid_selector}
        true -> {:ok, components}
      end
    else
      _ -> {:error, :invalid_selector}
    end
  end

  defp safe_json(json) do
    case JSON.decode(json) do
      {:ok, list} when is_list(list) and length(list) >= 3 -> {:ok, list}
      _ -> :error
    end
  end

  defp valid_components?(components) do
    length(components) in 1..4 and
      Enum.all?(components, fn
        c when is_integer(c) -> true
        c when is_binary(c) -> byte_size(c) <= 128 and String.valid?(c)
        _ -> false
      end)
  end

  @doc "Canonical fingerprint of the selector minus cursor/page_size."
  def fingerprint(%Selector{} = sel) do
    sel
    |> Map.from_struct()
    |> Map.drop([:cursor, :page_size])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, @fp_bytes)
    |> Base.url_encode64(padding: false)
  end
end
