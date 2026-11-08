defmodule DigitalOilSticker.QR.ZplTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.QR.Zpl

  @url "https://digitaloilsticker.com/s#ABCDEFGH23456789"

  describe "render/2" do
    test "emits a complete ZPL label framed by ^XA and ^XZ" do
      assert {:ok, zpl} = Zpl.render(@url, [])
      assert String.starts_with?(zpl, "^XA")
      assert String.ends_with?(zpl, "^XZ\n")
    end

    test "uses the ^BQ QR command (model 2) with the default magnification" do
      {:ok, zpl} = Zpl.render(@url, [])
      # ^BQN,2,6 — normal orientation, model 2, magnification 6 (the default).
      assert zpl =~ "^BQN,2,6"
    end

    test "carries the URL verbatim after the ^FDQA prefix" do
      {:ok, zpl} = Zpl.render(@url, [])
      # ZPL expects the data field to be prefixed with the error-correction
      # + mode indicator (QA = "quality A, auto"), then the raw URL.
      assert zpl =~ "^FDQA," <> @url
    end

    test "honors a custom magnification" do
      {:ok, zpl} = Zpl.render(@url, magnification: 8)
      assert zpl =~ "^BQN,2,8"
    end

    test "rejects out-of-range magnification with :invalid_magnification" do
      assert {:error, :invalid_magnification} = Zpl.render(@url, magnification: 0)
      assert {:error, :invalid_magnification} = Zpl.render(@url, magnification: 11)
      assert {:error, :invalid_magnification} = Zpl.render(@url, magnification: "big")
    end
  end
end
