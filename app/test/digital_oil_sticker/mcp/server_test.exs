defmodule DigitalOilSticker.Mcp.ServerTest do
  @moduledoc """
  Pure dispatch tests — no HTTP, no network. If the dispatch layer is sound,
  the HTTP transport is a thin wrapper and the integration test can be
  shallow.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Mcp.Server

  @key "11111111-2222-4333-8444-555555555555"

  describe "initialize" do
    test "returns protocol version, server info, and tool capability" do
      req = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}

      resp = Server.handle(req)

      assert resp[:jsonrpc] == "2.0"
      assert resp[:id] == 1
      assert resp[:result][:protocolVersion] == "2024-11-05"
      assert resp[:result][:serverInfo][:name] == "digital-oil-sticker"
      assert resp[:result][:capabilities][:tools] != nil
    end
  end

  describe "initialized notification" do
    test "returns nil (no response for notifications)" do
      req = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
      assert Server.handle(req) == nil
    end
  end

  describe "tools/list" do
    test "returns every tool with name, description, and inputSchema" do
      req = %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
      resp = Server.handle(req)

      tools = resp[:result][:tools]
      names = Enum.map(tools, & &1.name)

      assert "generate_sticker" in names
      assert "get_sticker" in names
      assert "list_formats" in names
      assert "parse_service_record" in names
      assert "get_integration_examples" in names

      for tool <- tools do
        assert is_binary(tool.description)
        assert is_map(tool.inputSchema)
        assert tool.inputSchema.type == "object"
      end
    end
  end

  describe "tools/call generate_sticker" do
    test "returns content with text + resource", %{} do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{
          "name" => "generate_sticker",
          "arguments" => %{
            "configuration_key" => @key,
            "changed_on" => "2026-11-08",
            "odometer_m" => 72_420_480,
            "grade" => "5W-30",
            "base_stock" => "full_synthetic",
            "format" => "png"
          }
        }
      }

      resp = Server.handle(req)

      refute resp[:result][:isError]
      content = resp[:result][:content]
      assert [text_item, resource_item] = content
      assert text_item.type == "text"
      assert String.contains?(text_item.text, "code=")
      assert resource_item.type == "resource"
      assert resource_item.resource.mimeType == "image/png"
      assert is_binary(resource_item.resource.blob)
    end

    test "returns isError: true with message on bad input" do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{
          "name" => "generate_sticker",
          "arguments" => %{"configuration_key" => "not-a-uuid"}
        }
      }

      resp = Server.handle(req)
      assert resp[:result][:isError] == true
      assert [%{type: "text", text: msg}] = resp[:result][:content]
      assert msg =~ "configuration_key"
    end
  end

  describe "tools/call list_formats" do
    test "returns a text listing of formats" do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "list_formats", "arguments" => %{}}
      }

      resp = Server.handle(req)
      refute resp[:result][:isError]
      assert [%{type: "text", text: text}] = resp[:result][:content]
      assert text =~ "png"
      assert text =~ "zpl"
    end
  end

  describe "tools/call get_integration_examples" do
    test "returns a curl snippet by default" do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "tools/call",
        "params" => %{"name" => "get_integration_examples", "arguments" => %{}}
      }

      resp = Server.handle(req)
      assert [%{type: "text", text: text}] = resp[:result][:content]
      assert text =~ "curl"
      assert text =~ "/api/v1/stickers"
    end

    test "returns language-specific examples when requested" do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_integration_examples",
          "arguments" => %{"language" => "python"}
        }
      }

      resp = Server.handle(req)
      assert [%{type: "text", text: text}] = resp[:result][:content]
      assert text =~ "import requests"
    end
  end

  describe "unknown method" do
    test "returns JSON-RPC method-not-found error" do
      req = %{"jsonrpc" => "2.0", "id" => 99, "method" => "fictional/method"}
      resp = Server.handle(req)
      assert resp[:error][:code] == -32601
      assert resp[:error][:message] =~ "fictional/method"
    end
  end

  describe "malformed request" do
    test "non-2.0 jsonrpc returns invalid request" do
      resp = Server.handle(%{"method" => "initialize", "id" => 1})
      assert resp[:error][:code] == -32600
    end
  end
end
