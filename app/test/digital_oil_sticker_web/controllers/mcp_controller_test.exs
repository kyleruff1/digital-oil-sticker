defmodule DigitalOilStickerWeb.McpControllerTest do
  @moduledoc """
  HTTP transport tests for the MCP endpoint at POST /mcp.

  The controller delegates to DigitalOilSticker.Mcp.Server.handle/1, which
  is tested in its own file (test/digital_oil_sticker/mcp/server_test.exs).
  This test covers only the controller's transport concerns: single-vs-batch
  body routing, notification handling (nil response → 204), empty-batch
  handling, parse error on malformed body, and that 200 responses carry
  the correct content-type.
  """
  use DigitalOilStickerWeb.ConnCase, async: true

  describe "POST /mcp — single request" do
    test "initialize returns 200 with a single response object and JSON content-type",
         %{conn: conn} do
      body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}

      conn = post(conn, "/mcp", body)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      resp = Jason.decode!(conn.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == 1
      assert resp["result"]["protocolVersion"] == "2024-11-05"
      refute is_list(resp)
    end
  end

  # Plug's test adapter converts a map params arg into form fields and a
  # list params arg into form tuples — neither is what the controller sees
  # in production for a JSON-RPC batch. The honest way to exercise the
  # batch path is to send a raw JSON body with content-type: application/json,
  # which Plug.Parsers.JSON then parses into conn.params["_json"] = [...].
  defp json_post(conn, path, term) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(term))
  end

  describe "POST /mcp — batch request" do
    test "list body returns 200 with an array of responses", %{conn: conn} do
      # A JSON array body arrives in conn.params as %{"_json" => [...]} by
      # Plug.Parsers' convention; the controller unwraps it.
      body = [
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"},
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
      ]

      conn = json_post(conn, "/mcp", body)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      resp = Jason.decode!(conn.resp_body)
      assert is_list(resp)
      assert length(resp) == 2
      assert Enum.any?(resp, &(&1["id"] == 1 and &1["result"]["protocolVersion"]))
      assert Enum.any?(resp, &(&1["id"] == 2 and is_list(&1["result"]["tools"])))
    end

    test "batch with notifications filters them from the response", %{conn: conn} do
      # A notification (no "id" field) returns nil from Server.handle/1 and
      # gets filtered out of the batch response — so a batch of one real
      # request + one notification returns a single-element array.
      body = [
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"},
        %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
      ]

      conn = json_post(conn, "/mcp", body)

      assert conn.status == 200
      resp = Jason.decode!(conn.resp_body)
      assert is_list(resp)
      assert length(resp) == 1
      assert hd(resp)["id"] == 1
    end
  end

  describe "POST /mcp — notifications and empty batch" do
    test "a lone notification request returns 204 with no body", %{conn: conn} do
      body = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

      conn = post(conn, "/mcp", body)

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "an empty batch returns 204 with no body", %{conn: conn} do
      conn = json_post(conn, "/mcp", [])

      assert conn.status == 204
      assert conn.resp_body == ""
    end
  end

  describe "POST /mcp — malformed body" do
    test "empty object body returns 400 with -32700 parse error", %{conn: conn} do
      # The controller rejects an empty map (map_size == 0) because it
      # cannot be a valid JSON-RPC request — missing both "jsonrpc" and
      # "method". The -32700 code is the JSON-RPC spec's "parse error."
      conn = post(conn, "/mcp", %{})

      assert conn.status == 400
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      resp = Jason.decode!(conn.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["error"]["code"] == -32700
      assert resp["error"]["message"] =~ "parse error"
    end
  end
end
