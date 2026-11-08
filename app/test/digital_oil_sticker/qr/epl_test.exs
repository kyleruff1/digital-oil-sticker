defmodule DigitalOilSticker.QR.EplTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR.Epl

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"

  describe "render/2" do
    test "starts with the N clear-buffer command and ends with P1" do
      assert {:ok, epl} = Epl.render(@url, [])
      assert String.starts_with?(epl, "N\n")
      assert String.ends_with?(epl, "P1\n")
    end

    test "uses the b command with Q (2D-QR) and the default coordinates" do
      {:ok, epl} = Epl.render(@url, [])
      # b<x>,<y>,Q,m2,s<ec>,eM,"<url>" — defaults x=50, y=50, ec=M.
      assert epl =~ "b50,50,Q,m2,sM,eM,"
    end

    test "carries the URL verbatim inside quotes" do
      {:ok, epl} = Epl.render(@url, [])
      assert epl =~ "\"" <> @url <> "\""
    end

    test "honors custom coordinates and error correction" do
      {:ok, epl} = Epl.render(@url, x: 100, y: 200, ec: :h)
      assert epl =~ "b100,200,Q,m2,sH,eM,"
    end
  end
end
