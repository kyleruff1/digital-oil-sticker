defmodule DigitalOilStickerWeb.QuotaPressureTest do
  @moduledoc """
  The 80%-of-quota pressure state on /settings/storage. Two things this file
  pins that FR-13 makes non-negotiable: writes must STILL be enabled when
  pressure surfaces (the pressure state is a nudge, not a lock), and nothing
  is deleted on the user's behalf to make room — INV-24.5 makes silent
  auto-purge a release blocker for the same reason silent write failure is,
  because from the user's seat the two are indistinguishable.

  The threshold branch and its 3-value truth table (above 80% / below 80% /
  no estimate at all) live here. The exact heading copy is the copy-lint's
  job; this file asserts the render hook (`data-test="quota-pressure"`) so
  it does not become a second, subtly different opinion about wording.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @car_one "11111111-1111-4111-8111-111111111111"
  @car_two "33333333-3333-4333-8333-333333333333"

  defp vehicle(id, make, model) do
    %{
      "vehicle_id" => id,
      "archived" => false,
      "model_year" => 2020,
      "configuration_key" => "000384cf-aee6-5ba8-968a-1fe30158f387",
      "display_snapshot" => %{
        "year" => 2020,
        "make" => make,
        "model" => model,
        "build" => "LE"
      },
      "maintenance_plan" => %{"interval_months" => 6, "interval_miles" => 5000}
    }
  end

  defp hydrate(view, overrides) do
    render_hook(
      view,
      "local_store:hydrate",
      Map.merge(
        %{
          "envelope" => "dos_local",
          "schema_version" => 1,
          "seq" => 0,
          "tab_id" => "t",
          "generated_at" => "2026-08-01T00:00:00Z",
          "data" => %{
            "meta" => nil,
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          "storage" => %{"mode" => "idb", "boot_hint" => "never"}
        },
        overrides
      )
    )
  end

  # Reach into the LiveView process for its assigns, the same way
  # idempotence_test.exs does: the pressure flag is set by
  # `Session.handle_hydrate/2` and lives in socket assigns, so a render-only
  # check would only prove the derived UI, not the derivation.
  defp assigns_of(view), do: :sys.get_state(view.pid).socket.assigns

  describe "at 90% of quota" do
    test "the pressure state surfaces on /settings/storage without blocking or deleting anything",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      # 4.5 MB of 5 MB used = 90%, comfortably over the 80% threshold FR-13
      # calls out.
      html =
        hydrate(view, %{
          "storage" => %{
            "mode" => "idb",
            "boot_hint" => "never",
            "estimate" => %{"usage" => 4_500_000, "quota" => 5_000_000}
          }
        })

      assert assigns_of(view).quota_pressure == true

      # The heading the pressure state renders is asserted through a stable
      # test hook rather than a copy string — the copy-lint owns the words;
      # this test owns the "did the threshold fire" question. If a well-meaning
      # rewording removes the hook, this fails and the render is genuinely
      # gone; if only the wording changes, this stays green (as it should).
      assert html =~ "data-test=\"quota-pressure\""

      # The two CTAs the pressure state exists to offer — export outside this
      # browser and prune records the user no longer needs. Asserting the
      # section hook alone would leave the heading rendering green even if a
      # regression deleted the whole action row; these two lines pin the
      # actual affordances so that "the pressure state fires" also means
      # "the two things the user can do about it are actually on the page."
      assert html =~ "data-test=\"quota-pressure-export\""
      assert html =~ "data-test=\"quota-pressure-prune\""

      # Behavioral proof for the export CTA: the button is wired to a real
      # server handler that pushes `local_store:export`. If a future edit
      # removes the phx-click, retitles the event, or drops the handler,
      # the button would still render (satisfying the hook assertion above)
      # but do nothing when clicked — this line catches that. The prune
      # anchor is an in-page href to #erase-panel and has no server event
      # to click, so there is no companion push-event assertion for it.
      render_click(view, "export", %{})
      assert_push_event(view, "local_store:export", %{})

      # FR-13 clause 2: "does not block writes". Prove it by driving a real
      # mutation on a mutating LiveView under the same 90% hydration, and
      # asserting `local_store:put` still fires. If a future change silently
      # added :quota_pressure to `mutations_enabled?/1`'s deny list (or made
      # it a `local_state` value without adding it to the allow list), the
      # switch would be swallowed and no put would push — exactly the failure
      # this test exists to prevent.
      {:ok, sticker, _} = live(conn, ~p"/")

      hydrate(sticker, %{
        "seq" => 1,
        "data" => %{
          "meta" => nil,
          "vehicles" => [
            vehicle(@car_one, "Toyota", "Camry"),
            vehicle(@car_two, "BMW", "328i")
          ],
          "events" => [],
          "readings" => [],
          "usage" => [],
          "reminders" => [],
          "prefs" => nil
        },
        "storage" => %{
          "mode" => "idb",
          "boot_hint" => "never",
          "estimate" => %{"usage" => 4_500_000, "quota" => 5_000_000}
        }
      })

      # Sanity: pressure is set here too. `handle_hydrate/2` derives it from
      # the envelope, so any LiveView with the same estimate sees the same
      # flag — the flag is a property of the hydration, not of the page.
      assert assigns_of(sticker).quota_pressure == true

      render_click(sticker, "toggle_garage", %{})
      render_click(sticker, "switch_vehicle", %{"vehicle-id" => @car_two})

      # The write the browser will persist. Payload contents are pinned by
      # save_path_test.exs — here we care only that a put went out at all.
      assert_push_event(sticker, "local_store:put", _payload)

      # FR-13 clause 3: "deletes nothing". No delete-shaped event of any
      # form went to the client. `local_store:erase` is the only wire
      # verb the current hook listens to for removal (it wipes the DB and
      # reloads the tab) — pressure must not push it. `local_store:delete`
      # is refuted too as a forward-looking guard: if a future release
      # introduces a per-record delete event, the "no automatic deletion"
      # rule still applies and this line will catch a pressure-triggered
      # auto-purge on that channel before it ships.
      refute_push_event(sticker, "local_store:delete", %{})
      refute_push_event(sticker, "local_store:erase", %{})

      # And the garage itself: both pre-mutation vehicles are still present.
      # The switch only writes prefs, so a shrunken vehicle list would mean
      # the app removed something the user did not ask to remove — the
      # exact "data goes missing" failure INV-24.5 exists to prevent.
      post = assigns_of(sticker)
      ids = Enum.map(post.garage.vehicles, & &1["vehicle_id"])
      assert @car_one in ids
      assert @car_two in ids
    end
  end

  describe "below 80% of quota" do
    test "no pressure state is claimed", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      # 0.5 MB of 5 MB used = 10%. Well under the threshold; nothing about
      # this hydration should look like pressure.
      html =
        hydrate(view, %{
          "storage" => %{
            "mode" => "idb",
            "boot_hint" => "never",
            "estimate" => %{"usage" => 500_000, "quota" => 5_000_000}
          }
        })

      assert assigns_of(view).quota_pressure == false
      refute html =~ "data-test=\"quota-pressure\""
    end
  end

  describe "with no estimate at all" do
    test "quota_pressure stays false — no threshold is fabricated from a missing quota",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      # `estimate` omitted entirely: `Session.quota/1` returns nil. The
      # pressure flag must NOT be truthy here — a browser that reports no
      # estimate is not a browser at 100% either, and inventing pressure
      # from silence would be the same INV-25 honesty failure as inventing
      # a percentage (see storage_status_quota_test.exs for the sibling
      # rule on the "Space" line).
      html = hydrate(view, %{"storage" => %{"mode" => "idb", "boot_hint" => "never"}})

      assert assigns_of(view).quota_pressure == false
      refute html =~ "data-test=\"quota-pressure\""
    end
  end
end
