defmodule DigitalOilSticker.Mcp.Server do
  @moduledoc """
  JSON-RPC 2.0 dispatch for the Model Context Protocol.

  MCP is a tiny protocol on top of JSON-RPC: a handshake
  (`initialize` → `initialized`), a few discovery methods (`tools/list`,
  `prompts/list`, `resources/list`), and `tools/call` which runs a tool
  and returns its `content` array.

  This module is transport-agnostic — `handle/1` takes a decoded JSON-RPC
  request map and returns a response map (or `nil` for notifications). The
  HTTP transport in `Mcp.TransportHttp` wraps this with JSON encoding and
  POST plumbing; a stdio transport, when we need one for local dev, can
  wrap the same function with newline-delimited framing.

  Keeping dispatch pure is what lets the whole surface be tested without
  ever opening a socket.
  """

  alias DigitalOilSticker.Mcp.Tools

  @protocol_version "2024-11-05"
  @server_info %{name: "digital-oil-sticker", version: "0.1.0"}

  @type request :: map()
  @type response :: map() | nil

  @doc """
  Dispatch a single decoded JSON-RPC request. Returns the response map, or
  `nil` for notifications (requests without an `id`).
  """
  @spec handle(request()) :: response()
  def handle(%{"jsonrpc" => "2.0"} = req) do
    method = Map.get(req, "method")
    params = Map.get(req, "params", %{})
    id = Map.get(req, "id")

    case dispatch(method, params) do
      {:ok, result} -> maybe_respond(id, %{jsonrpc: "2.0", id: id, result: result})
      {:error, code, message} -> error_response(id, code, message)
      :notify -> nil
    end
  end

  # Malformed request object (missing or wrong jsonrpc version). Spec says
  # respond with an error even if we can't tell what id the client used
  # (null id is valid); but for a request that doesn't look like JSON-RPC
  # at all, we skip — no client should be surprised by a 204.
  def handle(req) when is_map(req) do
    id = Map.get(req, "id")

    if Map.has_key?(req, "method") or Map.has_key?(req, "jsonrpc") do
      error_response(id, -32600, "invalid request")
    else
      nil
    end
  end

  def handle(_), do: nil

  # -- method dispatch ---------------------------------------------------------

  defp dispatch("initialize", _params) do
    {:ok,
     %{
       protocolVersion: @protocol_version,
       serverInfo: @server_info,
       capabilities: %{tools: %{listChanged: false}}
     }}
  end

  defp dispatch("initialized", _params), do: :notify
  defp dispatch("notifications/initialized", _params), do: :notify

  defp dispatch("ping", _params), do: {:ok, %{}}

  defp dispatch("tools/list", _params) do
    {:ok, %{tools: Tools.list()}}
  end

  defp dispatch("tools/call", %{"name" => name, "arguments" => args}) do
    case Tools.call(name, args || %{}) do
      {:ok, content} -> {:ok, %{content: content, isError: false}}
      {:error, message} -> {:ok, %{content: [%{type: "text", text: message}], isError: true}}
    end
  end

  defp dispatch("tools/call", _params), do: {:error, -32602, "invalid tools/call params"}

  defp dispatch("prompts/list", _), do: {:ok, %{prompts: []}}
  defp dispatch("resources/list", _), do: {:ok, %{resources: []}}
  defp dispatch("resources/templates/list", _), do: {:ok, %{resourceTemplates: []}}

  defp dispatch(nil, _), do: {:error, -32600, "missing method"}
  defp dispatch(method, _), do: {:error, -32601, "method not found: #{method}"}

  # -- response helpers --------------------------------------------------------

  # Notifications (no id) get no response, even on success.
  defp maybe_respond(nil, _), do: nil
  defp maybe_respond(_id, resp), do: resp

  defp error_response(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
