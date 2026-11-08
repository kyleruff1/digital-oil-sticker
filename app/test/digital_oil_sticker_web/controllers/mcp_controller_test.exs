defmodule DigitalOilStickerWeb.McpControllerTest do
  use DigitalOilStickerWeb.ConnCase, async: true

  @key "11111111-2222-4333-8444-555555555555"

  describe "POST /mcp" do
    test "end-to-end: initialize → tools/list → tools/call", %{conn: conn} do
      # 1. initialize
      conn1 =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "initialize"}))

      assert %{"result" => %{"protocolVersion" => _, "serverInfo" => info}} =
               json_response(conn1, 200)

      assert info["name"] == "digital-oil-sticker"

      # 2. tools/list
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 2, method: "tools/list"}))

      assert %{"result" => %{"tools" => tools}} = json_response(conn2, 200)
      assert Enum.any?(tools, &(&1["name"] == "generate_sticker"))

      # 3. tools/call generate_sticker
      conn3 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            id: 3,
            method: "tools/call",
            params: %{
              name: "generate_sticker",
              arguments: %{
                configuration_key: @key,
                grade: "5W-30",
                format: "svg"
              }
            }
          })
        )

      assert %{"result" => %{"content" => content, "isError" => false}} =
               json_response(conn3, 200)

      assert Enum.any?(content, &(&1["type"] == "resource"))
    end

    test "notification (no id) returns 204", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/mcp",
          Jason.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"})
        )

      assert conn.status == 204
    end

    test "an empty body returns a JSON-RPC parse error", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", "")

      assert %{"error" => %{"code" => -32700}} = json_response(conn, 400)
    end
  end
end
