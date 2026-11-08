defmodule DigitalOilSticker.QR.Epl do
  @moduledoc """
  QR → EPL (Eltron Programming Language).

  Older Eltron/Zebra units that predate ZPL support ship with EPL instead.
  The `b` command places a 2D barcode; for a QR we pass `Q`, a model, and
  the data. Useful for legacy shop floors — a lot of independent repair
  shops are still running first-generation Zebra-branded Eltron units.

      N                  ; clear buffer
      q<width-dots>      ; label width
      Q<height-dots>,<gap>  ; label length and gap
      b<x>,<y>,Q,m<module-size>,s<ec>,"<data>"
      P1                 ; print 1 copy
  """

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def render(url, opts) when is_binary(url) do
    x = Keyword.get(opts, :x, 50)
    y = Keyword.get(opts, :y, 50)
    _module_size = Keyword.get(opts, :module_size, 6)
    ec = ec_char(Keyword.get(opts, :ec, :m))

    epl =
      IO.iodata_to_binary([
        "N\n",
        "b",
        Integer.to_string(x),
        ",",
        Integer.to_string(y),
        ",Q,m2,s",
        ec,
        ",eM,",
        "\"",
        url,
        "\"\n",
        "P1\n"
      ])

    {:ok, epl}
  end

  defp ec_char(:l), do: "L"
  defp ec_char(:m), do: "M"
  defp ec_char(:q), do: "Q"
  defp ec_char(:h), do: "H"
end
