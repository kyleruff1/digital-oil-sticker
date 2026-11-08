defmodule DigitalOilSticker.Grok.ParseServiceTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Grok.ParseService

  @key "11111111-2222-4333-8444-555555555555"

  # Reusable stub builders. Shape matches xAI's OpenAI-compatible response.
  defp chat_response(tool_call_args) do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call_1",
                "type" => "function",
                "function" => %{
                  "name" => "record_service",
                  "arguments" => Jason.encode!(tool_call_args)
                }
              }
            ]
          }
        }
      ]
    }
  end

  defp prose_response(content) do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => content,
            "tool_calls" => []
          }
        }
      ]
    }
  end

  defp stub_response(json) do
    Req.Test.stub(DigitalOilSticker.Grok.Client, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(json))
    end)
  end

  setup do
    # XAI_API_KEY must be set (even to a dummy value) for the client to make
    # the call — the plug stub intercepts before anything hits the network.
    original = System.get_env("XAI_API_KEY")
    System.put_env("XAI_API_KEY", "test-key")

    on_exit(fn ->
      if original do
        System.put_env("XAI_API_KEY", original)
      else
        System.delete_env("XAI_API_KEY")
      end
    end)

    :ok
  end

  describe "parse/2" do
    test "extracts grade and odometer from free text and merges in the key" do
      stub_response(
        chat_response(%{
          "grade" => "5W-30",
          "base_stock" => "full_synthetic",
          "odometer" => 45_000,
          "odometer_unit" => "mi",
          "changed_on" => "2026-11-08"
        })
      )

      assert {:ok, params} =
               ParseService.parse(
                 "Full synthetic 5W-30, 45,000 miles, changed today",
                 @key
               )

      assert params["configuration_key"] == @key
      assert params["grade"] == "5W-30"
      assert params["base_stock"] == "full_synthetic"
      assert params["odometer"] == 45_000
      assert params["odometer_unit"] == "mi"
      assert params["changed_on"] == "2026-11-08"
    end

    test "returns :no_tool_call when Grok replies in prose" do
      stub_response(prose_response("I'm not sure what you meant."))

      assert {:error, :no_tool_call} = ParseService.parse("gibberish", @key)
    end

    test "returns :no_api_key without a network trip when XAI_API_KEY is absent" do
      System.delete_env("XAI_API_KEY")
      assert {:error, :no_api_key} = ParseService.parse("5W-30", @key)
    end

    test "returns {:http_error, status} when xAI returns non-200" do
      Req.Test.stub(DigitalOilSticker.Grok.Client, fn conn ->
        Plug.Conn.send_resp(conn, 500, ~s|{"error":"server error"}|)
      end)

      assert {:error, {:http_error, 500}} = ParseService.parse("5W-30", @key)
    end

    test "returns :transport_error on network failure" do
      Req.Test.stub(DigitalOilSticker.Grok.Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :transport_error} = ParseService.parse("5W-30", @key)
    end
  end
end
