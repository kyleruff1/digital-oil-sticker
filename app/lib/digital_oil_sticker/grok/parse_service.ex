defmodule DigitalOilSticker.Grok.ParseService do
  @moduledoc """
  Natural-language parser for service records. Converts "5W-30 full
  synthetic, 45,230 miles, next change in 5000 miles" into the fields
  `Sticker.from_params/1` consumes.

  Uses Grok with function calling: the model's only legal output is a tool
  call whose arguments match the sticker schema. Anything the model omits
  is left out — `Sticker.from_params/1` and `StickerCode.encode/1` are the
  validators, not this module.

  The `configuration_key` is NEVER parsed from the text: a POS integration
  already knows which vehicle this is. The caller passes `configuration_key`
  explicitly and we merge it with whatever Grok returned.
  """

  alias DigitalOilSticker.Grok.Client
  alias DigitalOilSticker.StickerCode

  @system_prompt """
  You extract vehicle service details from informal shop notes into a
  structured sticker record. Only call the record_service tool — never answer
  in prose. If a field is not clearly stated, omit it. Never guess an oil
  grade from "synthetic" alone; grade means a specific viscosity like 5W-30.
  """

  @tool_schema %{
    type: "function",
    function: %{
      name: "record_service",
      description: "Record the extracted service details so a sticker can be generated.",
      parameters: %{
        type: "object",
        properties: %{
          changed_on: %{
            type: "string",
            format: "date",
            description: "ISO 8601 date of the oil change (YYYY-MM-DD)."
          },
          odometer_m: %{
            type: "integer",
            description: "Odometer at service, in whole metres (canonical)."
          },
          odometer: %{
            type: "number",
            description: "Odometer at service — pair with odometer_unit."
          },
          odometer_unit: %{
            type: "string",
            enum: ["mi", "km"],
            description: "Unit for odometer. Required when odometer is given."
          },
          grade: %{
            type: "string",
            enum: StickerCode.grades(),
            description: "Viscosity grade, one of the enum values."
          },
          base_stock: %{
            type: "string",
            enum: StickerCode.base_stocks(),
            description: "Oil base stock, one of the enum values."
          }
        },
        additionalProperties: false
      }
    }
  }

  @doc """
  Parse `text` into param keys (string-keyed, suitable for
  `Sticker.from_params/1`). `configuration_key` must be supplied by the
  caller; it never comes from the text.

  Returns `{:ok, params_map}` on success; `{:error, reason}` otherwise.
  The reason set includes `:no_api_key`, `:transport_error`,
  `{:http_error, status}`, `:invalid_response`, and `:no_tool_call` (the
  model answered in prose instead of calling the tool).
  """
  @spec parse(String.t(), String.t()) ::
          {:ok, map()} | {:error, atom() | {atom(), term()}}
  def parse(text, configuration_key) when is_binary(text) and is_binary(configuration_key) do
    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: text}
    ]

    with {:ok, %{tool_calls: [first | _]}} <-
           Client.chat(messages, [@tool_schema], tool_choice: "auto"),
         {:ok, args} <- extract_args(first) do
      {:ok, Map.put(args, "configuration_key", configuration_key)}
    else
      {:ok, %{tool_calls: []}} -> {:error, :no_tool_call}
      {:error, _} = e -> e
    end
  end

  defp extract_args(%{"function" => %{"arguments" => args}}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_response}
    end
  end

  defp extract_args(_), do: {:error, :invalid_response}
end
