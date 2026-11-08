defmodule DigitalOilStickerWeb.Api.V1.StickerController do
  @moduledoc """
  The public integration surface. A POS/DMS/CRM system calls this at the end
  of a work order and receives a ready-to-print QR sticker in the format its
  printer already speaks.

  Everything the API knows is in `DigitalOilSticker.StickerCode.encode/1`'s
  record plus a format name. There is no account, no session, no shop row
  server-side — just the deterministic pipeline:

      params  ─▶ Sticker.from_params/1
              ─▶ StickerCode.encode/1  (validation)
              ─▶ Sticker.canonical_url/2
              ─▶ QR.render(url, format, opts)
              ─▶ response

  The body on POST may be `application/json`. On GET the code lives in the
  path (`/api/v1/stickers/:code.:format`), so the response is a pure
  function of the URL and is safely cacheable.
  """
  use DigitalOilStickerWeb, :controller

  alias DigitalOilSticker.{Grok, QR, Sticker, StickerCode}
  alias DigitalOilStickerWeb.Hosts

  @doc """
  POST /api/v1/stickers

  Body: JSON with the sticker fields plus `format`. Returns the code, the
  canonical URL, and the rendered output (as a response body when the format
  is bytes, or as a base64 data URI when the client asked for JSON).
  """
  def create(conn, params) do
    with {:ok, format} <- QR.parse_format(Map.get(params, "format", "png")),
         {:ok, sticker} <- Sticker.from_params(params),
         {:ok, code} <- StickerCode.encode(sticker),
         url = Sticker.canonical_url(code, Hosts.canonical()),
         {:ok, rendered} <- QR.render(url, format, render_opts(params)) do
      respond(conn, format, code, url, rendered, wants_json?(params))
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  @doc """
  POST /api/v1/stickers/from-text

  Body: `{ configuration_key, text, format? }`. Grok parses the free text
  into structured service fields; we merge in the caller-supplied
  configuration_key and generate the sticker through the same pipeline as
  POST /stickers.

  503 when `XAI_API_KEY` is not configured — the structured endpoint still
  works regardless.
  """
  def from_text(conn, params) do
    with {:ok, format} <- QR.parse_format(Map.get(params, "format", "png")),
         {:ok, text} <- require_text(params),
         {:ok, key} <- require_key(params),
         {:ok, parsed} <- Grok.ParseService.parse(text, key),
         {:ok, sticker} <- Sticker.from_params(parsed),
         {:ok, code} <- StickerCode.encode(sticker),
         url = Sticker.canonical_url(code, Hosts.canonical()),
         {:ok, rendered} <- QR.render(url, format, render_opts(params)) do
      respond(conn, format, code, url, rendered, wants_json?(params))
    else
      {:error, :no_api_key} -> json_error(conn, 503, :grok_not_configured)
      {:error, :no_tool_call} -> json_error(conn, 422, :could_not_parse_text)
      {:error, :transport_error} -> json_error(conn, 502, :grok_unreachable)
      {:error, {:http_error, _}} -> json_error(conn, 502, :grok_error)
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp require_text(params) do
    case Map.get(params, "text") do
      s when is_binary(s) and byte_size(s) > 0 -> {:ok, s}
      _ -> {:error, :missing_text}
    end
  end

  defp require_key(params) do
    case Map.get(params, "configuration_key") do
      s when is_binary(s) and byte_size(s) > 0 -> {:ok, s}
      _ -> {:error, :missing_configuration_key}
    end
  end

  @doc """
  GET /api/v1/stickers/:code.:format

  Idempotent, cache-friendly. The code is the whole payload; the server
  never writes a row, so the only state consulted is the format allowlist.
  """
  def show(conn, %{"code_with_ext" => code_with_ext}) do
    with {:ok, code, format_str} <- split_code_ext(code_with_ext),
         {:ok, format} <- QR.parse_format(format_str),
         {:ok, _sticker} <- StickerCode.decode(code),
         url = Sticker.canonical_url(code, Hosts.canonical()),
         {:ok, rendered} <- QR.render(url, format, render_opts(conn.query_params)) do
      conn
      |> put_cache_headers()
      |> put_resp_content_type(content_type_for(format))
      |> send_resp(200, rendered)
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  # Split "ABCDEF.png" into {"ABCDEF", "png"}. The code is always
  # unpadded base32 — [A-Z2-7]+ — so the first dot is the extension's.
  defp split_code_ext(s) when is_binary(s) do
    case String.split(s, ".", parts: 2) do
      [code, ext] when byte_size(code) > 0 and byte_size(ext) > 0 -> {:ok, code, ext}
      _ -> {:error, :invalid_request}
    end
  end

  @doc """
  OPTIONS preflight. `CORSPlug` in the pipeline already handles the response
  headers and halts the connection, so this action never actually runs — the
  route exists only so Phoenix will enter the pipeline instead of 404'ing
  before cors_plug can respond.
  """
  def preflight(conn, _params), do: send_resp(conn, 204, "")

  # -- response helpers --------------------------------------------------------

  defp respond(conn, _format, code, url, rendered, true = _wants_json) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        code: code,
        url: url,
        data: Base.encode64(rendered)
      })
    )
  end

  defp respond(conn, format, code, url, rendered, false) do
    conn
    |> put_resp_header("x-sticker-code", code)
    |> put_resp_header("x-sticker-url", url)
    |> put_resp_content_type(content_type_for(format))
    |> send_resp(200, rendered)
  end

  defp wants_json?(params), do: Map.get(params, "output") == "json"

  defp render_opts(params) do
    [width: integer_opt(params, "width", 320)]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp integer_opt(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      n when is_integer(n) ->
        n

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} -> n
          _ -> default
        end

      _ ->
        default
    end
  end

  defp content_type_for(:png), do: "image/png"
  defp content_type_for(:svg), do: "image/svg+xml"
  defp content_type_for(:zpl), do: "application/vnd.zebra.zpl"
  defp content_type_for(:esc_pos), do: "application/octet-stream"
  defp content_type_for(:epl), do: "application/vnd.zebra.epl"
  defp content_type_for(:tspl), do: "application/vnd.tsc.tspl"

  defp put_cache_headers(conn) do
    # The code IS the content — no two codes produce the same output, so this
    # answer will never change. A long immutable cache makes CDN-side caching
    # trivial and keeps our server off the hot path for repeated scans.
    conn
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
  end

  defp send_error(conn, :unknown_format), do: json_error(conn, 400, :unknown_format)
  defp send_error(conn, :invalid_params), do: json_error(conn, 400, :invalid_params)

  defp send_error(conn, :missing_configuration_key),
    do: json_error(conn, 422, :missing_configuration_key)

  defp send_error(conn, :invalid_configuration_key),
    do: json_error(conn, 422, :invalid_configuration_key)

  defp send_error(conn, :invalid_date), do: json_error(conn, 422, :invalid_date)
  defp send_error(conn, :date_out_of_range), do: json_error(conn, 422, :date_out_of_range)
  defp send_error(conn, :odometer_out_of_range), do: json_error(conn, 422, :odometer_out_of_range)
  defp send_error(conn, :invalid_grade), do: json_error(conn, 422, :invalid_grade)
  defp send_error(conn, :invalid_base_stock), do: json_error(conn, 422, :invalid_base_stock)
  defp send_error(conn, :url_too_long), do: json_error(conn, 400, :url_too_long)
  defp send_error(conn, :invalid_magnification), do: json_error(conn, 400, :invalid_magnification)
  defp send_error(conn, :invalid_size), do: json_error(conn, 400, :invalid_size)
  defp send_error(conn, :missing_text), do: json_error(conn, 400, :missing_text)
  defp send_error(conn, :could_not_parse_text), do: json_error(conn, 422, :could_not_parse_text)
  defp send_error(conn, _other), do: json_error(conn, 400, :invalid_request)

  defp json_error(conn, status, atom_reason) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: Atom.to_string(atom_reason)}))
  end
end
