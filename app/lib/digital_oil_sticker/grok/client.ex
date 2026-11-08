defmodule DigitalOilSticker.Grok.Client do
  @moduledoc """
  Thin `Req` wrapper around xAI's OpenAI-compatible chat API.

  Only three things are configurable:

    * `XAI_API_KEY` — the bearer token (required to call `chat/4`; absent
      keys produce `{:error, :no_api_key}` without a network trip),
    * `XAI_MODEL` — defaults to `grok-4-latest`,
    * `XAI_BASE_URL` — defaults to `https://api.x.ai/v1`. Tests point it at
      a `Req.Test.stub/2`.

  Grok is NEVER in the sticker-generation hot path. This module exists to
  parse free-text service records and, later, to power the MCP server's
  optional `parse_service_record` tool. Keep that discipline: no helper here
  should feel like a general-purpose LLM utility, because importing one into
  the sticker POST path is how we'd silently add dollar-cost and latency to
  the fast lane.
  """

  @default_base_url "https://api.x.ai/v1"
  @default_model "grok-4-latest"

  @type message :: %{role: String.t(), content: String.t()}
  @type tool :: map()

  @type chat_result ::
          {:ok, %{content: String.t() | nil, tool_calls: [map()]}}
          | {:error,
             :no_api_key | :invalid_response | {:http_error, pos_integer()} | :transport_error}

  @doc """
  Send a chat-completions request. On success returns the first choice's
  message, split into `:content` (may be nil when the model emits tool
  calls only) and `:tool_calls` (always a list, possibly empty).
  """
  @spec chat([message()], [tool()], keyword()) :: chat_result()
  def chat(messages, tools \\ [], opts \\ []) when is_list(messages) do
    with {:ok, key} <- api_key() do
      body =
        %{
          model: Keyword.get(opts, :model, model()),
          messages: messages
        }
        |> maybe_put(:tools, tools)
        |> maybe_put(:tool_choice, Keyword.get(opts, :tool_choice))
        |> maybe_put(:temperature, Keyword.get(opts, :temperature))

      req_opts =
        [
          base_url: base_url(),
          url: "/chat/completions",
          method: :post,
          json: body,
          auth: {:bearer, key},
          receive_timeout: Keyword.get(opts, :timeout, 30_000)
        ]
        |> Keyword.merge(configured_req_options())
        |> Keyword.merge(Keyword.get(opts, :req_options, []))

      case Req.request(req_opts) do
        {:ok, %{status: 200, body: body}} -> parse_body(body)
        {:ok, %{status: status}} -> {:error, {:http_error, status}}
        {:error, _} -> {:error, :transport_error}
      end
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp api_key do
    case System.get_env("XAI_API_KEY") do
      nil -> {:error, :no_api_key}
      "" -> {:error, :no_api_key}
      key -> {:ok, key}
    end
  end

  defp base_url, do: System.get_env("XAI_BASE_URL") || @default_base_url
  defp model, do: System.get_env("XAI_MODEL") || @default_model

  # Lets tests inject a `plug: {Req.Test, Name}` without touching production.
  defp configured_req_options do
    Application.get_env(:digital_oil_sticker, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, []), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp parse_body(%{"choices" => [%{"message" => msg} | _]}) do
    {:ok,
     %{
       content: Map.get(msg, "content"),
       tool_calls: Map.get(msg, "tool_calls", [])
     }}
  end

  defp parse_body(_), do: {:error, :invalid_response}
end
