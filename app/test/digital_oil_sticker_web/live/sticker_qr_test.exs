defmodule DigitalOilStickerWeb.StickerQrTest do
  @moduledoc """
  The scannable code on the front page.

  Two properties carry this surface, and neither is visible by looking at it:

    * what the symbol encodes is what the sticker says — a QR that decodes to a
      different odometer than the one printed above it is worse than no QR,
      because someone will trust it, and
    * the code lives in the URL fragment, so the values never reach a server
      log (INV-26). A path would put them there and nothing would look wrong.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.StickerCode

  # A configuration key the catalog actually ships, so the vehicle resembles one
  # a user could really have selected.
  @config_key "000384cf-aee6-5ba8-968a-1fe30158f387"
  @vehicle_id "11111111-1111-4111-8111-111111111111"

  defp hydrate(view, data) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => Map.get(data, "seq", 1),
      "tab_id" => "test-tab",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" =>
        Map.merge(
          %{
            "meta" => nil,
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          Map.delete(data, "seq")
        ),
      "storage" => %{"mode" => "idb", "boot_hint" => "never"}
    })
  end

  defp vehicle(overrides \\ %{}) do
    Map.merge(
      %{
        "vehicle_id" => @vehicle_id,
        "archived" => false,
        "model_year" => 2020,
        "configuration_key" => @config_key,
        "maintenance_plan" => %{
          "basis" => "user_entered",
          "interval_months" => 6,
          "interval_miles" => 5000
        }
      },
      overrides
    )
  end

  defp event(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => "22222222-2222-4222-8222-222222222222",
        "vehicle_id" => @vehicle_id,
        "performed_at" => "2026-06-15",
        "odometer_m" => 80_467_200,
        "odometer_input_value" => "50,000",
        "input_unit" => "mi",
        "oil_viscosity" => "5W-30",
        "oil_base_stock" => "full_synthetic",
        "provenance_mode" => "manual"
      },
      overrides
    )
  end

  defp payload_from(html) do
    case Regex.run(~r/data-payload="([^"]+)"/, html) do
      [_, payload] -> payload
      _ -> nil
    end
  end

  defp printed_key(html) do
    case Regex.run(~r/data-test="sticker-qr-key">([^<]*)</, html) do
      [_, key] -> key
      _ -> nil
    end
  end

  describe "what the symbol carries" do
    test "decodes back to exactly the values the sticker shows", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

      "https://" <> rest = payload_from(html)
      [_host_and_path, code] = String.split(rest, "#", parts: 2)

      assert {:ok, decoded} = StickerCode.decode(code)

      # Each of these is also rendered as text on the sticker. A divergence
      # here means the scan autofills something the user is not looking at.
      assert decoded.configuration_key == @config_key
      assert decoded.changed_on == ~D[2026-06-15]
      assert decoded.odometer_m == 80_467_200
      assert decoded.grade == "5W-30"
      assert decoded.base_stock == "full_synthetic"

      assert html =~ "5W-30"
      assert html =~ "Jun 15, 2026"
    end

    test "the printed key is byte-for-byte what the symbol carries", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

      "https://" <> rest = payload_from(html)
      [_, code] = String.split(rest, "#", parts: 2)

      # Printed with no grouping or separators on purpose: the moment the
      # printed form differs from the accepted form, the fallback the printing
      # exists for stops working, and it fails for a human who is doing
      # exactly what the sticker invited them to do.
      assert printed_key(html) == code
      assert {:ok, _} = StickerCode.decode(printed_key(html))
    end

    test "changes when a newer oil change is logged", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      first = hydrate(view, %{"seq" => 1, "vehicles" => [vehicle()], "events" => [event()]})

      newer =
        event(%{
          "event_id" => "33333333-3333-4333-8333-333333333333",
          "performed_at" => "2026-07-20",
          "odometer_m" => 88_514_000,
          "oil_viscosity" => "0W-20"
        })

      second =
        hydrate(view, %{"seq" => 2, "vehicles" => [vehicle()], "events" => [event(), newer]})

      refute payload_from(first) == payload_from(second)

      "https://" <> rest = payload_from(second)
      [_, code] = String.split(rest, "#", parts: 2)

      assert {:ok, %{grade: "0W-20", changed_on: ~D[2026-07-20]}} = StickerCode.decode(code)
    end
  end

  describe "where the code sits in the URL" do
    test "is in the fragment, so it never reaches a server log", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

      payload = payload_from(html)
      [before_hash, after_hash] = String.split(payload, "#", parts: 2)

      # The part before the "#" is everything a server, a proxy, and every
      # access log in between will see. The code — and therefore the odometer,
      # the service date, and the grade — must not be in it.
      assert before_hash == "https://#{DigitalOilStickerWeb.Hosts.canonical()}/s"
      refute before_hash =~ after_hash
      assert String.match?(after_hash, ~r/^[A-Z2-7]+$/)
    end

    test "carries no personal value as a query parameter", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

      payload = payload_from(html)
      [before_hash, _] = String.split(payload, "#", parts: 2)

      refute before_hash =~ "?"
      refute before_hash =~ "80467200"
      refute before_hash =~ "5W-30"
      refute before_hash =~ @config_key
    end
  end

  describe "when a code cannot be made" do
    test "a vehicle with no catalog configuration gets no symbol at all", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      html =
        hydrate(view, %{
          "vehicles" => [Map.delete(vehicle(), "configuration_key")],
          "events" => [event()]
        })

      # Fail closed. A symbol built on a guessed key would resolve to a vehicle
      # the user never chose, and it would scan perfectly while doing it.
      refute html =~ "data-test=\"sticker-qr\""
      refute html =~ "data-payload"

      # The sticker itself still renders — losing the QR must not lose the
      # record.
      assert html =~ "5W-30"
    end

    test "a vehicle with no oil change yet still gets a code for the vehicle", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => []})

      "https://" <> rest = payload_from(html)
      [_, code] = String.split(rest, "#", parts: 2)

      # Every service field absent, and that round-trips as absent rather than
      # as a zero odometer or an epoch date.
      assert {:ok, decoded} = StickerCode.decode(code)
      assert decoded.configuration_key == @config_key
      assert decoded.changed_on == nil
      assert decoded.odometer_m == nil
      assert decoded.grade == nil
    end
  end

  describe "the surface itself" do
    test "is absent before hydration, when there is nothing to encode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      refute html =~ "data-test=\"sticker-qr\""
    end

    test "announces itself rather than presenting an unlabeled image", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

      assert html =~ ~s(role="img")
      assert html =~ DigitalOilStickerWeb.Copy.qr_alt()
    end

    test "does not claim the scan moves anything", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

      assert html =~ "does not move what is stored in this browser"
    end
  end
end
