defmodule DigitalOilSticker.Mcp.Tools do
  @moduledoc """
  The five tools the MCP server exposes.

  Each tool has a JSON Schema input, a handler that returns `{:ok, content}`
  or `{:error, message}`, and a one-line summary a Grok or Claude agent
  reads to decide whether to call it.

  Handlers reach into the same domain modules the REST controllers do —
  `Sticker.from_params/1`, `StickerCode.encode/1`, `QR.render/3`,
  `Grok.ParseService.parse/2` — so both surfaces share one truth about
  what a sticker is.
  """

  alias DigitalOilSticker.{Grok, QR, Sticker, StickerCode}

  # The MCP server lives in the domain layer (reachable from Claude/Grok
  # agents regardless of whether the Phoenix endpoint even starts), so it
  # cannot reference the web-layer `Hosts` module. The host is read from
  # the same environment variable `Hosts.canonical/0` reads, with the same
  # fly.dev fallback — the two stay in agreement by using the same env.
  @fly_fallback_host "digital-oil-sticker.fly.dev"

  @doc "List every tool's declaration (name, description, inputSchema)."
  def list do
    [
      %{
        name: "generate_sticker",
        description:
          "Generate a QR sticker for a service record. Returns the sticker code and the rendered output in the requested format (png, svg, zpl, esc_pos, epl, or tspl). Format defaults to png.",
        inputSchema: %{
          type: "object",
          required: ["configuration_key"],
          properties: %{
            configuration_key: %{
              type: "string",
              description: "The catalog UUID for this vehicle configuration."
            },
            changed_on: %{type: "string", format: "date"},
            odometer_m: %{type: "integer"},
            odometer: %{type: "number"},
            odometer_unit: %{type: "string", enum: ["mi", "km"]},
            grade: %{type: "string", enum: StickerCode.grades()},
            base_stock: %{type: "string", enum: StickerCode.base_stocks()},
            format: %{
              type: "string",
              enum: Enum.map(QR.formats(), &Atom.to_string/1),
              default: "png"
            }
          }
        }
      },
      %{
        name: "get_sticker",
        description:
          "Render an existing sticker code in the requested format. Pure function of (code, format) — the code IS the sticker.",
        inputSchema: %{
          type: "object",
          required: ["code"],
          properties: %{
            code: %{type: "string"},
            format: %{
              type: "string",
              enum: Enum.map(QR.formats(), &Atom.to_string/1),
              default: "png"
            }
          }
        }
      },
      %{
        name: "list_formats",
        description: "List the output formats the sticker renderer supports.",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "parse_service_record",
        description:
          "Parse a free-text service note into structured sticker fields using Grok. The caller must still supply configuration_key — the text is only for service details.",
        inputSchema: %{
          type: "object",
          required: ["configuration_key", "text"],
          properties: %{
            configuration_key: %{type: "string"},
            text: %{type: "string"}
          }
        }
      },
      %{
        name: "get_integration_examples",
        description:
          "Return copy-pasteable curl and code examples for calling the sticker API from a POS or shop-management system.",
        inputSchema: %{
          type: "object",
          properties: %{
            language: %{
              type: "string",
              enum: ["curl", "node", "python", "elixir"],
              default: "curl"
            }
          }
        }
      }
    ]
  end

  @doc "Dispatch a tools/call. Returns {:ok, content} or {:error, message}."
  @spec call(String.t(), map()) :: {:ok, [map()]} | {:error, String.t()}
  def call("generate_sticker", args) do
    format_str = Map.get(args, "format", "png")

    with {:ok, format} <- QR.parse_format(format_str),
         {:ok, sticker} <- Sticker.from_params(args),
         {:ok, code} <- StickerCode.encode(sticker),
         url = Sticker.canonical_url(code, host()),
         {:ok, rendered} <- QR.render(url, format, []) do
      {:ok,
       [
         text(
           "Sticker generated. code=#{code} url=#{url} format=#{format} bytes=#{byte_size(rendered)}"
         ),
         resource(url, format, rendered)
       ]}
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  def call("get_sticker", args) do
    format_str = Map.get(args, "format", "png")
    code = Map.get(args, "code", "")

    with {:ok, format} <- QR.parse_format(format_str),
         {:ok, _sticker} <- StickerCode.decode(code),
         url = Sticker.canonical_url(code, host()),
         {:ok, rendered} <- QR.render(url, format, []) do
      {:ok, [text("code=#{code} url=#{url} format=#{format}"), resource(url, format, rendered)]}
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  def call("list_formats", _args) do
    body =
      QR.formats()
      |> Enum.map_join("\n", &"- #{&1}")

    {:ok, [text("Supported formats:\n" <> body)]}
  end

  def call("parse_service_record", args) do
    text_in = Map.get(args, "text", "")
    key = Map.get(args, "configuration_key", "")

    cond do
      text_in == "" ->
        {:error, "text is required"}

      key == "" ->
        {:error, "configuration_key is required"}

      true ->
        case Grok.ParseService.parse(text_in, key) do
          {:ok, params} -> {:ok, [text(Jason.encode!(params))]}
          {:error, :no_api_key} -> {:error, "Grok is not configured on this server."}
          {:error, :no_tool_call} -> {:error, "Could not extract service fields from the text."}
          {:error, reason} -> {:error, "Grok error: #{inspect(reason)}"}
        end
    end
  end

  def call("get_integration_examples", args) do
    language = Map.get(args, "language", "curl")
    {:ok, [text(example_for(language))]}
  end

  def call(name, _args), do: {:error, "unknown tool: #{name}"}

  # -- helpers -----------------------------------------------------------------

  defp host, do: System.get_env("PHX_HOST") || @fly_fallback_host

  defp text(s), do: %{type: "text", text: s}

  defp resource(url, format, bytes) do
    %{
      type: "resource",
      resource: %{
        uri: url,
        mimeType: mime_for(format),
        blob: Base.encode64(bytes)
      }
    }
  end

  defp mime_for(:png), do: "image/png"
  defp mime_for(:svg), do: "image/svg+xml"
  defp mime_for(:zpl), do: "application/vnd.zebra.zpl"
  defp mime_for(:esc_pos), do: "application/octet-stream"
  defp mime_for(:epl), do: "application/vnd.zebra.epl"
  defp mime_for(:tspl), do: "application/vnd.tsc.tspl"

  defp error_message(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp error_message(other), do: inspect(other)

  defp example_for("curl") do
    """
    curl -X POST https://digitaloilsticker.com/api/v1/stickers \\
      -H 'Content-Type: application/json' \\
      --output sticker.png \\
      -d '{
        "configuration_key": "<catalog-uuid>",
        "changed_on": "2026-11-08",
        "odometer": 45000,
        "odometer_unit": "mi",
        "grade": "5W-30",
        "base_stock": "full_synthetic",
        "format": "png"
      }'
    """
  end

  defp example_for("node") do
    """
    const res = await fetch("https://digitaloilsticker.com/api/v1/stickers", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        configuration_key: "<catalog-uuid>",
        changed_on: "2026-11-08",
        odometer: 45000, odometer_unit: "mi",
        grade: "5W-30", base_stock: "full_synthetic",
        format: "zpl"
      })
    });
    const zpl = await res.text();
    // Send zpl to the shop's Zebra printer.
    """
  end

  defp example_for("python") do
    """
    import requests
    r = requests.post("https://digitaloilsticker.com/api/v1/stickers", json={
        "configuration_key": "<catalog-uuid>",
        "changed_on": "2026-11-08",
        "odometer": 45000, "odometer_unit": "mi",
        "grade": "5W-30", "base_stock": "full_synthetic",
        "format": "esc_pos"
    })
    # r.content is the ESC/POS byte stream — send to the receipt printer.
    """
  end

  defp example_for("elixir") do
    """
    {:ok, resp} = Req.post("https://digitaloilsticker.com/api/v1/stickers",
      json: %{
        configuration_key: "<catalog-uuid>",
        changed_on: "2026-11-08",
        odometer: 45_000, odometer_unit: "mi",
        grade: "5W-30", base_stock: "full_synthetic",
        format: "svg"
      })
    # resp.body is the SVG string.
    """
  end

  defp example_for(_), do: example_for("curl")
end
