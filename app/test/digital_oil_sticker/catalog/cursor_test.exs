defmodule DigitalOilSticker.Catalog.CursorTest do
  @moduledoc "AC-8: gapless keyset pagination, stale cursors, adversarial decode."
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{Cursor, Selector}

  defp sel(params) do
    {:ok, s} = Selector.validate(:list_models, params)
    s
  end

  test "page-walk is gapless, duplicate-free, and terminates" do
    {:ok, first} = Selector.validate(:list_makes, %{"year" => 2024, "page_size" => 3})
    {:ok, r1} = Catalog.list_makes(first)
    assert length(r1.data) <= 3

    all =
      Stream.unfold({first, :start}, fn
        {_s, nil} ->
          nil

        {s, cursor} ->
          params = %{"year" => 2024, "page_size" => 3}
          params = if cursor == :start, do: params, else: Map.put(params, "cursor", cursor)
          {:ok, s2} = Selector.validate(:list_makes, params)
          {:ok, r} = Catalog.list_makes(s2)
          {r.data, {s, r.cursor}}
      end)
      |> Enum.to_list()
      |> List.flatten()

    ids = Enum.map(all, & &1.id)
    assert ids == Enum.uniq(ids)
    assert length(ids) == r1.total
  end

  test "a cursor from one data_version is stale under another" do
    s = sel(%{"year" => 2024, "make_id" => "abc"})
    cursor = Cursor.encode(["somename", "someid"], s)

    encoded =
      cursor
      |> Base.url_decode64!(padding: false)
      |> JSON.decode!()
      |> List.replace_at(1, "some-other-version")
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    assert {:error, :stale_cursor} = Cursor.decode(encoded, s)
  end

  test "a cursor replayed against a different query is invalid, not silently honored" do
    s2024 = sel(%{"year" => 2024, "make_id" => "abc"})
    s1997 = sel(%{"year" => 1997, "make_id" => "abc"})
    cursor = Cursor.encode(["name", "id"], s2024)
    assert {:error, :invalid_selector} = Cursor.decode(cursor, s1997)
  end

  test "adversarial cursors error without crashing" do
    s = sel(%{"year" => 2024, "make_id" => "abc"})

    for bad <- [
          Base.url_encode64("' OR 1=1--", padding: false),
          "not-base64!!!",
          Base.url_encode64("[1]", padding: false),
          Base.url_encode64("{\"a\":1}", padding: false),
          Base.url_encode64(JSON.encode!([1, "v", "fp", %{"nested" => true}]), padding: false),
          String.duplicate("A", 512)
        ] do
      assert {:error, :invalid_selector} = Cursor.decode(bad, s)
    end
  end
end
