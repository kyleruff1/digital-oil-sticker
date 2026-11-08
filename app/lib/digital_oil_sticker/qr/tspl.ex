defmodule DigitalOilSticker.QR.Tspl do
  @moduledoc """
  QR → TSPL (TSC Printer Language).

  TSC and a long tail of compatible thermal printers (Argox, Godex, some
  Rongta units) speak TSPL. The `QRCODE` command places a native QR; the
  printer encodes the matrix itself, same as ZPL.

      SIZE 2.0,1.0            ; label size in inches
      GAP 0.12,0              ; gap between labels
      CLS                     ; clear buffer
      QRCODE <x>,<y>,<ec>,<cell_width>,<mode>,<rotation>,"<data>"
      PRINT 1                 ; print 1 copy

  Error correction codes: `L`/`M`/`Q`/`H`. Mode `A` = auto-detect data type.
  """

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def render(url, opts) when is_binary(url) do
    x = Keyword.get(opts, :x, 50)
    y = Keyword.get(opts, :y, 50)
    cell_width = Keyword.get(opts, :cell_width, 6)
    ec = ec_char(Keyword.get(opts, :ec, :m))

    tspl =
      IO.iodata_to_binary([
        "SIZE 2.0,1.0\n",
        "GAP 0.12,0\n",
        "CLS\n",
        "QRCODE ",
        Integer.to_string(x),
        ",",
        Integer.to_string(y),
        ",",
        ec,
        ",",
        Integer.to_string(cell_width),
        ",A,0,",
        "\"",
        url,
        "\"\n",
        "PRINT 1\n"
      ])

    {:ok, tspl}
  end

  defp ec_char(:l), do: "L"
  defp ec_char(:m), do: "M"
  defp ec_char(:q), do: "Q"
  defp ec_char(:h), do: "H"
end
