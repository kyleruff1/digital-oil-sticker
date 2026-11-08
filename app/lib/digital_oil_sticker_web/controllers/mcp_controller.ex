defmodule DigitalOilStickerWeb.McpController do
  @moduledoc """
  Streamable-HTTP transport for the MCP server.

  One endpoint, `POST /mcp`, accepts a JSON-RPC 2.0 request body (either a
  single object or a batch array) and returns the response(s). This is the
  simplest transport MCP allows — no SSE stream needed for our tool set
  because every tool completes synchronously in milliseconds.

  Later, if a tool grows a streaming output (progress during a long Grok
  call, say), we add a `GET /mcp` SSE endpoint and bump this controller to
  the full streamable-HTTP spec.
  """
  use DigitalOilStickerWeb, :controller

  alias DigitalOilSticker.Mcp.Server

  def handle(conn, params) do
    # Phoenix's JSON body parser has already decoded the request body into
    # params. A batch JSON-RPC request (a top-level array) lands in
    # conn.body_params as %{"_json" => [...]} — that's Plug.Parsers' idiom
    # for a non-object JSON body.
    decoded =
      case Map.get(params, "_json") do
        list when is_list(list) -> list
        _ -> conn.body_params
      end

    case decoded do
      map when is_map(map) and map_size(map) > 0 ->
        respond(conn, dispatch(map))

      list when is_list(list) ->
        respond(conn, dispatch(list))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            jsonrpc: "2.0",
            id: nil,
            error: %{code: -32700, message: "parse error"}
          })
        )
    end
  end

  # Batch: array of requests → array of responses (drop nils for notifications).
  defp dispatch(batch) when is_list(batch) do
    batch
    |> Enum.map(&Server.handle/1)
    |> Enum.reject(&is_nil/1)
  end

  defp dispatch(single) when is_map(single), do: Server.handle(single)

  # No content for a notification or empty batch.
  defp respond(conn, nil), do: send_resp(conn, 204, "")
  defp respond(conn, []), do: send_resp(conn, 204, "")

  defp respond(conn, response) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end
end
