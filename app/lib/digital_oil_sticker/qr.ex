defmodule DigitalOilSticker.QR do
  @moduledoc """
  Multi-format QR rendering. One entry point, one output format per call.

  The input is always the canonical scanner URL — the thing the QR encodes,
  not the sticker map. The caller (web controller, MCP tool, or a test) has
  already called `Sticker.canonical_url/2` and knows which host the sticker
  belongs to.

  Formats:

    * `:png`      — a PNG byte string, suitable for inlining via a data URI
                    or writing to a file
    * `:svg`      — an SVG string, fine for inlining into HTML or saving
    * `:zpl`      — Zebra Programming Language, printer-native QR command
                    (works on any ZPL-compatible label printer: Zebra,
                    some Honeywell, many knock-offs)
    * `:esc_pos`  — Epson/Star thermal receipt-printer bytes, printer-native
                    QR command (GS ( k)
    * `:epl`      — older Eltron/Zebra EPL (`b` command)
    * `:tspl`     — TSC command set (`QRCODE`)

  The printer-native formats (zpl/esc_pos/epl/tspl) carry the URL as the QR's
  text payload. The printer itself encodes the matrix. This is deliberately
  smaller than a raster: a printer encoding a URL into a native QR is cheaper
  than us rasterizing the matrix and sending kilobytes of pixels, and the
  shop's existing printer firmware is the only decoder we never have to
  update.

  `:png` and `:svg` go through `EQRCode` because the caller renders them —
  a browser inlines an SVG, a PDF embeds a PNG, a web view shows a data
  URI — and those decoders need an actual rastered or vectored symbol.
  """

  @type format :: :png | :svg | :zpl | :esc_pos | :epl | :tspl
  @type options :: keyword()

  @formats [:png, :svg, :zpl, :esc_pos, :epl, :tspl]

  @doc "Every format `render/3` accepts. Public so the `/api/v1/formats` endpoint reads it from one place."
  @spec formats() :: [format()]
  def formats, do: @formats

  @doc """
  Render `url` as a QR in `format`. Returns `{:ok, iodata_or_binary}` or
  `{:error, atom}`. The content type of the result depends on the format and
  is the caller's job to set:

      :png     → "image/png"           (binary)
      :svg     → "image/svg+xml"       (binary)
      :zpl     → "application/zpl"     (binary, ASCII)
      :esc_pos → "application/octet-stream" (binary, printer bytes)
      :epl     → "application/epl"     (binary, ASCII)
      :tspl    → "application/tspl"    (binary, ASCII)
  """
  @spec render(String.t(), format(), options()) ::
          {:ok, binary()} | {:error, :unknown_format | :url_too_long}
  def render(url, format, opts \\ [])

  def render(url, :png, opts), do: __MODULE__.Png.render(url, opts)
  def render(url, :svg, opts), do: __MODULE__.Svg.render(url, opts)
  def render(url, :zpl, opts), do: __MODULE__.Zpl.render(url, opts)
  def render(url, :esc_pos, opts), do: __MODULE__.EscPos.render(url, opts)
  def render(url, :epl, opts), do: __MODULE__.Epl.render(url, opts)
  def render(url, :tspl, opts), do: __MODULE__.Tspl.render(url, opts)
  def render(_, _, _), do: {:error, :unknown_format}

  @doc "Parse a format name from an API param. Accepts atoms and strings."
  @spec parse_format(term()) :: {:ok, format()} | {:error, :unknown_format}
  def parse_format(f) when f in @formats, do: {:ok, f}

  def parse_format(s) when is_binary(s) do
    case Enum.find(@formats, fn f -> Atom.to_string(f) == s end) do
      nil -> {:error, :unknown_format}
      f -> {:ok, f}
    end
  end

  def parse_format(_), do: {:error, :unknown_format}
end
