defmodule DigitalOilStickerWeb.LocalStore.PersistLifecycleTest do
  @moduledoc """
  AC-9-test / G8: the persistence-request lifecycle is a fire-once guard
  measured across the socket, not the click.

  Session.init/1 sets `:persist_requested` to false. It stays false through
  hydration alone — hydration is not a user act, and firing a UA prompt on
  every remount would train users to dismiss it. On the FIRST staged
  mutation, `stage_mutation/4` pipes through `maybe_auto_request_persist/1`,
  which flips `:persist_requested` to true and pushes exactly one
  `local_store:request_persist` to the browser. Every subsequent mutation on
  the same socket is silent: the guard has already fired, and re-asking the
  UA is both noisy and no better than the manual override on
  /settings/storage.

  Once the client answers with `local_store:persist_result`, the LocalStore
  on_mount hook records the outcome in `:persist_granted` — true for
  "granted", false for "denied", nil for anything else ("unavailable" is the
  no-persist-API path). INV-25 is the reason the rendered copy on
  /settings/storage must describe every one of those states without
  promising anything the browser did not: no "backed up", no "backup", no
  "safe/safely stored", no "durable". Persistence is a hint the UA is free
  to ignore under pressure, and the page has to admit that.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @car_one "11111111-1111-4111-8111-111111111111"
  @car_two "22222222-2222-4222-8222-222222222222"

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 3,
    "tab_id" => "tab-persist-lifecycle",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 3},
      "vehicles" => [
        %{
          "vehicle_id" => @car_one,
          "nickname" => "Camry",
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{"year" => 2020, "make" => "Toyota", "model" => "Camry"}
        },
        %{
          "vehicle_id" => @car_two,
          "nickname" => "BMW",
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{"year" => 2020, "make" => "BMW", "model" => "328i"}
        }
      ],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      # Deliberately omit "persist_granted" here so hydration leaves the
      # assign nil — the state where `maybe_auto_request_persist/1` fires.
      "prefs" => %{"unit_system" => "mi", "active_vehicle_id" => @car_one}
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp hydrate_storage(view) do
    render_hook(view, "local_store:hydrate", %{
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
    })
  end

  # Strip every HTML tag so the substring checks only see the prose the user
  # actually reads. Without this, `refute html =~ "safe"` would trip on
  # Tailwind's `motion-safe:animate-spin` class in the layout's
  # connection-status flashes — and `\bsafe\b` still matches inside the
  # class token because `-` is a regex word boundary. INV-25 governs
  # visible copy, not incidental class names, so we compare against visible
  # copy directly.
  defp visible_text(html), do: Regex.replace(~r/<[^>]*>/, html, " ")

  defp refute_dishonest_persist_copy(html) do
    text = visible_text(html)
    refute text =~ "backed up"
    refute text =~ "backup"
    refute text =~ "safely stored"
    # `\bsafe\w*\b` (case-insensitive) catches "safe", "Safe", "safer",
    # "safest", "safety" — INV-25 rules out the whole family, not just the
    # bare word, because "your data is safely stored" and "kept safer" make
    # the same broken promise.
    refute text =~ ~r/\bsafe\w*\b/i
    # `\bdurab\w*\b` catches "durable", "durability", "durably" for the same
    # reason — a hint the UA may drop is not a durability guarantee under
    # any suffix.
    refute text =~ ~r/\bdurab\w*\b/i
  end

  test "hydration alone leaves persist_requested false and pushes no request_persist",
       %{conn: conn} do
    # Mounting a mutating LiveView and hydrating a valid envelope is not the
    # user asking to save anything — it is the app reading what is already
    # in the browser. Firing a UA persistence prompt here would train users
    # to dismiss it before they ever intend to keep data.
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @envelope)

    a = assigns(view)
    assert a.local_state == :loaded

    assert a.persist_requested == false,
           "hydration must not flip the fire-once guard — only a staged mutation may"

    assert a.persist_granted == nil,
           "envelope omitted persist_granted so the assign must stay nil"

    refute_push_event(view, "local_store:request_persist", %{})
  end

  test "the first mutation pushes exactly one request_persist and flips persist_requested",
       %{conn: conn} do
    # Drive the switcher on / to stage a real prefs mutation — same code
    # path a user click runs, so `stage_mutation` fires
    # `maybe_auto_request_persist/1` the way it does in production.
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "local_store:hydrate", @envelope)

    assert assigns(view).persist_requested == false

    render_click(view, "toggle_garage", %{})
    render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

    # The put and the persistence request both come out of stage_mutation on
    # the first-write path. Consuming the put here keeps the mailbox tidy
    # for the second-mutation test above but is not strictly necessary — the
    # request_persist assertion is the load-bearing one.
    assert_push_event(view, "local_store:put", _put_payload)
    assert_push_event(view, "local_store:request_persist", %{})

    # Even inside the SAME single-mutation window — between the
    # stage_mutation call and the end of this assertion block — no second
    # request_persist may be emitted. Test 3 covers a subsequent mutation;
    # this refute covers the narrower claim that a single first-write path
    # emits exactly one request_persist, not two. A bug where
    # `maybe_auto_request_persist` fired both before the guard check and
    # again after the flip would slip past test 3 but would be caught here.
    refute_push_event(view, "local_store:request_persist", %{})

    assert assigns(view).persist_requested == true,
           "maybe_auto_request_persist must flip the guard on the first mutation"
  end

  test "a second mutation does NOT push another request_persist", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "local_store:hydrate", @envelope)

    # First mutation: fires the guarded request.
    render_click(view, "toggle_garage", %{})
    render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

    assert_push_event(view, "local_store:put", _first_put)
    assert_push_event(view, "local_store:request_persist", %{})
    assert assigns(view).persist_requested == true

    # Second mutation on the same socket — the switcher runs again, so
    # `stage_mutation` runs again, so `maybe_auto_request_persist/1` runs
    # again. The guard is the whole point: this second call MUST NOT emit
    # another request_persist. A regression that dropped the
    # `persist_requested == false` check would show up right here.
    render_click(view, "switch_vehicle", %{"vehicle-id" => @car_one})

    assert_push_event(view, "local_store:put", _second_put)
    refute_push_event(view, "local_store:request_persist", %{})

    assert assigns(view).persist_requested == true,
           "the guard must stay flipped across every subsequent mutation"
  end

  describe "persist_result on /settings/storage" do
    test "granted -> persist_granted true, no dishonest persistence copy renders",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      hydrate_storage(view)

      html = render_hook(view, "local_store:persist_result", %{"result" => "granted"})

      assert assigns(view).persist_granted == true
      refute_dishonest_persist_copy(html)

      # INV-25 constrains the whole app's visible copy, not just
      # /settings/storage. Even in the "granted" state — the most tempting
      # one to describe with backup/safe/durable framing — a non-settings
      # LiveView like / must not smuggle those promises in either.
      {:ok, home_view, home_html} = live(conn, ~p"/")
      hydrate_storage(home_view)
      refute_dishonest_persist_copy(home_html)
      refute_dishonest_persist_copy(render(home_view))
    end

    test "denied -> persist_granted false, no dishonest persistence copy renders",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      hydrate_storage(view)

      html = render_hook(view, "local_store:persist_result", %{"result" => "denied"})

      assert assigns(view).persist_granted == false
      refute_dishonest_persist_copy(html)

      # Denied is the state most likely to leak reassurance copy ("still
      # safe", "still backed up") elsewhere in the app to soften the news.
      # Non-/settings/storage LiveViews must stay honest too.
      {:ok, home_view, home_html} = live(conn, ~p"/")
      hydrate_storage(home_view)
      refute_dishonest_persist_copy(home_html)
      refute_dishonest_persist_copy(render(home_view))
    end

    test "unavailable -> persist_granted nil, no dishonest persistence copy renders",
         %{conn: conn} do
      # `"unavailable"` is neither "granted" nor "denied" so the hook maps
      # it to nil — the honest "we could not ask" state, which the page
      # still has to describe without borrowing backup/safe/durable framing.
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      hydrate_storage(view)

      html = render_hook(view, "local_store:persist_result", %{"result" => "unavailable"})

      assert assigns(view).persist_granted == nil
      refute_dishonest_persist_copy(html)

      # The "unavailable" state has no reassuring outcome to describe, so
      # any backup/safe/durable copy on / would be an outright lie. Verify
      # the non-settings surface holds the line.
      {:ok, home_view, home_html} = live(conn, ~p"/")
      hydrate_storage(home_view)
      refute_dishonest_persist_copy(home_html)
      refute_dishonest_persist_copy(render(home_view))
    end
  end
end
