defmodule DigitalOilStickerWeb.Api.V1.StickerControllerTest do
  use DigitalOilStickerWeb.ConnCase, async: true

  @key "11111111-2222-4333-8444-555555555555"

  @canonical_body %{
    "configuration_key" => @key,
    "changed_on" => "2026-11-01",
    "odometer_m" => 72_420_480,
    "grade" => "5W-30",
    "base_stock" => "full_synthetic"
  }

  describe "GET /api/v1/formats" do
    test "lists every supported format with content types", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/formats")
      assert %{"formats" => formats} = json_response(conn, 200)

      names = Enum.map(formats, & &1["name"])
      assert "png" in names
      assert "svg" in names
      assert "zpl" in names
      assert "esc_pos" in names
      assert "epl" in names
      assert "tspl" in names

      png_entry = Enum.find(formats, &(&1["name"] == "png"))
      assert png_entry["content_type"] == "image/png"
    end
  end

  describe "POST /api/v1/stickers" do
    test "returns PNG bytes by default", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/stickers", @canonical_body)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
      # PNG signature
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = conn.resp_body
      # Code echoed in header for POS callers who want to store it alongside the sticker
      assert [code] = get_resp_header(conn, "x-sticker-code")
      assert String.length(code) >= 20
      assert [url] = get_resp_header(conn, "x-sticker-url")
      assert String.starts_with?(url, "https://")
      assert String.contains?(url, "/s#")
    end

    test "returns ZPL when format=zpl", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/stickers", Map.put(@canonical_body, "format", "zpl"))

      assert conn.status == 200
      body = conn.resp_body
      assert String.starts_with?(body, "^XA")
      assert String.contains?(body, "^BQN,2,")
    end

    test "returns ESC/POS when format=esc_pos", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/stickers", Map.put(@canonical_body, "format", "esc_pos"))

      assert conn.status == 200
      assert <<0x1D, 0x28, 0x6B, _::binary>> = conn.resp_body
    end

    test "returns JSON envelope when output=json", %{conn: conn} do
      body = @canonical_body |> Map.put("format", "png") |> Map.put("output", "json")
      conn = post(conn, ~p"/api/v1/stickers", body)

      assert %{"code" => code, "url" => url, "data" => data_b64} = json_response(conn, 200)
      assert is_binary(code)
      assert String.starts_with?(url, "https://")
      # The base64 decodes back to PNG bytes
      {:ok, bytes} = Base.decode64(data_b64)
      assert <<137, 80, 78, 71, _rest::binary>> = bytes
    end

    test "rejects missing configuration_key with 422", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/stickers", %{"grade" => "5W-30"})

      # from_params normalizes to a map with configuration_key: nil, so the
      # error that bubbles up is `invalid_configuration_key` — the UUID
      # validator ran and rejected nil.
      assert %{"error" => "invalid_configuration_key"} = json_response(conn, 422)
    end

    test "rejects an invalid date with 422", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/stickers", %{
          "configuration_key" => @key,
          "changed_on" => "not-a-date"
        })

      assert %{"error" => "invalid_date"} = json_response(conn, 422)
    end

    test "rejects an unknown format with 400", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/stickers", Map.put(@canonical_body, "format", "gif"))

      assert %{"error" => "unknown_format"} = json_response(conn, 400)
    end
  end

  describe "GET /api/v1/stickers/:code.:format" do
    setup %{conn: conn} do
      response_conn = post(conn, ~p"/api/v1/stickers", @canonical_body)
      [code] = get_resp_header(response_conn, "x-sticker-code")
      %{code: code}
    end

    test "returns PNG for a known code", %{conn: conn, code: code} do
      conn = get(conn, "/api/v1/stickers/#{code}.png")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
      assert <<137, 80, 78, 71, _rest::binary>> = conn.resp_body
    end

    test "returns ZPL for a known code with .zpl", %{conn: conn, code: code} do
      conn = get(conn, "/api/v1/stickers/#{code}.zpl")

      assert conn.status == 200
      assert String.starts_with?(conn.resp_body, "^XA")
    end

    test "sets immutable cache headers (code IS the content)", %{conn: conn, code: code} do
      conn = get(conn, "/api/v1/stickers/#{code}.png")

      assert [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control == "public, max-age=31536000, immutable"
    end

    test "rejects an unknown format with 400", %{conn: conn, code: code} do
      conn = get(conn, "/api/v1/stickers/#{code}.gif")
      assert json_response(conn, 400) == %{"error" => "unknown_format"}
    end

    test "rejects a bogus code with 400", %{conn: conn} do
      conn = get(conn, "/api/v1/stickers/not-a-code.png")
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "CORS" do
    test "OPTIONS preflight succeeds from any origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://app.tekmetric.com")
        |> put_req_header("access-control-request-method", "POST")
        |> options(~p"/api/v1/stickers")

      assert conn.status in [200, 204]
      allow_origin = get_resp_header(conn, "access-control-allow-origin")
      assert allow_origin == ["*"] or allow_origin == ["https://app.tekmetric.com"]
    end
  end
end
