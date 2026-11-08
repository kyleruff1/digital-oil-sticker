defmodule DigitalOilSticker.QR.TsplTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR.Tspl

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"

  describe "render/2" do
    test "emits the SIZE/GAP/CLS header, QRCODE command, and PRINT footer" do
      assert {:ok, tspl} = Tspl.render(@url, [])
      assert tspl =~ "SIZE 2.0,1.0\n"
      assert tspl =~ "GAP 0.12,0\n"
      assert tspl =~ "CLS\n"
      assert tspl =~ "QRCODE "
      assert tspl =~ "PRINT 1\n"
    end

    test "uses the default args: x=50, y=50, ec=M, cell_width=6, mode=A, rotation=0" do
      {:ok, tspl} = Tspl.render(@url, [])
      # QRCODE <x>,<y>,<ec>,<cell_width>,<mode>,<rotation>,"<data>"
      assert tspl =~ "QRCODE 50,50,M,6,A,0,"
    end

    test "carries the URL verbatim inside quotes" do
      {:ok, tspl} = Tspl.render(@url, [])
      assert tspl =~ "\"" <> @url <> "\""
    end

    test "honors custom coordinates, cell_width, and EC level" do
      {:ok, tspl} = Tspl.render(@url, x: 10, y: 20, cell_width: 4, ec: :h)
      assert tspl =~ "QRCODE 10,20,H,4,A,0,"
    end
  end
end
