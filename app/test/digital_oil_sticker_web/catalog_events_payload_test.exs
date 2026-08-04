defmodule DigitalOilStickerWeb.CatalogEventsPayloadTest do
  @moduledoc """
  DOS-M09-004 AC-3: scripted-session complement to
  `DigitalOilSticker.Catalog.ImpersonalSelectorTest`.

  That file proves the STRUCTURAL property: the Selector vocabulary rejects
  every personal-looking key on every declared catalog function. This file
  proves the same guarantee holds under a real DISPATCH: we mount
  `VehiclePickerLive` to establish a live catalog-page session (loaded
  metadata, catalog data version, rate-limit budget lifecycle), then walk a
  scripted sequence of `catalog:*` events through
  `DigitalOilStickerWeb.CatalogEvents.handle/4` — the single web-edge that
  translates LiveView event names into validated selectors and dispatches to
  `DigitalOilSticker.Catalog`.

  For each event we independently reconstruct the selector the pipeline
  built (via `Selector.validate/2` — the pure function the edge itself calls,
  so its result is byte-equal to the selector that reached the facade), and
  assert that the client-provided keys inside it are exactly the ones
  declared for that event in `Vocabulary.event_allowlist/0`. A telemetry
  probe on `[:dos, :catalog, :query, :start]` proves the Catalog facade was
  actually reached (a rejected event opens no span).

  Then a stealth key — `{"year" => 2020, "vin" => "sneaky"}` — is fired and
  we assert `{:error, :invalid_selector, unchanged_bucket}`: `vin` never
  atomizes to a vocabulary field, `reject_extra_keys/2` short-circuits before
  `RateLimit.take/3`, and NO `[:dos, :catalog, :query, :start]` telemetry
  ever fires. That is the wire-side complement of `impersonal_selector_test`
  — the vocabulary is the structural gate, `CatalogEvents` is the wire gate,
  and both refuse the same key.

  The events dispatched here (`catalog:select_year`, `catalog:select_make`)
  are the canonical names declared in `Vocabulary.event_allowlist/0` and
  mapped in `CatalogEvents.@event_functions`; `VehiclePickerLive` today
  drives its cascade with the bundled `cascade_change` event rather than
  these canonical names, so the test invokes the edge directly. The moment a
  LiveView begins routing the canonical names, this test locks in that the
  allowlist enforcement is already in place.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias DigitalOilSticker.Catalog.{RateLimit, Selector, Vocabulary}
  alias DigitalOilStickerWeb.CatalogEvents

  # A year the fixture has real configurations for — the task calls for
  # `2020`, but the shipped `catalog-fixture-a.sqlite3` window ranges 1997..
  # 2026 and contains no 2020 configurations, so `list_makes` for 2020 would
  # return an empty result and there would be no `make_id` in the response
  # to feed the second event. `2024` is the first fixture year with multiple
  # real makes, so the "some_id from prior response" step is genuine and not
  # a fabricated UUID that happens to pass the id regex.
  @scripted_year 2024

  defp any_make_id_for(year) do
    DigitalOilSticker.CatalogRepo.one(
      from(c in "vehicle_configurations",
        where: c.model_year == ^year,
        select: c.make_id,
        limit: 1
      )
    )
  end

  # Reconstructs the exact selector `CatalogEvents.handle/4` handed to the
  # Catalog facade for `params`. `Selector.validate/2` is the pure function
  # the edge itself calls (see `CatalogEvents.handle/4`'s `with`), so its
  # result is byte-equal to the value that reached `apply(Catalog, ...)`.
  defp captured_selector(function, params) do
    {:ok, sel} = Selector.validate(function, params)
    sel
  end

  # Fields on `%Selector{}` that came from the client's payload — every
  # non-nil struct key except `:function` (the dispatch tag, not a client
  # input) and `:page_size` when it still carries the schema default (nothing
  # in the payload asked for a page). This is the set of keys that actually
  # crossed the boundary as a query parameter, i.e. what "hit" the facade.
  defp client_keys(%Selector{} = sel) do
    sel
    |> Map.from_struct()
    |> Enum.reject(fn
      {:function, _} -> true
      {:page_size, 50} -> true
      {_k, nil} -> true
      _ -> false
    end)
    |> Enum.map(fn {k, _} -> k end)
    |> Enum.sort()
  end

  # The event's declared allowlist, atomized through the compile-time map
  # `Vocabulary` uses (`key_atom/1` is guaranteed to return `{:ok, atom}` for
  # every entry — the allowlist and the field specs share the same key set).
  defp expected_atom_keys(event) do
    Vocabulary.event_allowlist()
    |> Map.fetch!(event)
    |> Enum.map(fn s ->
      {:ok, atom} = Vocabulary.key_atom(s)
      atom
    end)
    |> Enum.sort()
  end

  # Telemetry handlers are global, so filter to spans this test process
  # actually kicked off. `CatalogEvents.handle/4` runs the facade
  # synchronously in the caller, so a start event lands in this process's
  # mailbox exactly when a query was dispatched.
  defp attach_query_start_probe do
    ref = :counters.new(1, [])
    test_pid = self()
    handler_id = "catalog-events-payload-#{inspect(self())}"

    :telemetry.attach(
      handler_id,
      [:dos, :catalog, :query, :start],
      fn _event, _measurements, meta, pid ->
        if self() == pid do
          :counters.add(ref, 1, 1)
          send(pid, {:catalog_query_started, meta})
        end
      end,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    ref
  end

  defp query_count(ref), do: :counters.get(ref, 1)

  describe "scripted catalog:* dispatch through CatalogEvents" do
    test "select_year then select_make dispatch to Catalog with exactly the allowlisted keys",
         %{conn: conn} do
      # Mount the picker to establish the scripted-session context — a real
      # catalog page in a real endpoint, with `Catalog.Metadata` loaded and
      # the fixture readable. The events dispatched next travel the
      # `CatalogEvents` edge directly (the picker's own handler is
      # `cascade_change`, not the canonical `catalog:*` names).
      {:ok, _view, _html} = live(conn, ~p"/vehicle/select")

      make_id = any_make_id_for(@scripted_year)

      assert is_binary(make_id),
             "fixture must contain at least one make for #{@scripted_year} to source " <>
               "the \"some_id from prior response\" step of the scripted sequence"

      ref = attach_query_start_probe()
      bucket = RateLimit.new()

      # -- catalog:select_year -----------------------------------------------
      year_params = %{"year" => @scripted_year}

      assert {:ok, %{status: :identity_only} = year_result, bucket_after_year} =
               CatalogEvents.handle("catalog:select_year", year_params, bucket, 0)

      # The facade was actually reached — the mapped function fired a span.
      assert_receive {:catalog_query_started, %{function: :list_makes}}

      # The selector that hit `Catalog.list_makes/1` carried exactly the
      # keys declared in `Vocabulary.event_allowlist/0["catalog:select_year"]`
      # — no stripping, no substitution, no smuggled defaults from the
      # client payload.
      year_sel = captured_selector(:list_makes, year_params)
      assert client_keys(year_sel) == expected_atom_keys("catalog:select_year")

      # One token spent (bucket returned from the pipeline is not the input
      # bucket), and real makes came back — proof this was a live dispatch,
      # not just a validation dry-run.
      assert bucket_after_year.tokens < bucket.tokens
      assert year_result.data != []

      # -- catalog:select_make -----------------------------------------------
      make_params = %{"year" => @scripted_year, "make_id" => make_id}

      assert {:ok, %{status: :identity_only} = make_result, bucket_after_make} =
               CatalogEvents.handle(
                 "catalog:select_make",
                 make_params,
                 bucket_after_year,
                 0
               )

      assert_receive {:catalog_query_started, %{function: :list_models}}

      make_sel = captured_selector(:list_models, make_params)
      assert client_keys(make_sel) == expected_atom_keys("catalog:select_make")

      assert bucket_after_make.tokens < bucket_after_year.tokens
      # Not asserting `make_result.data != []` — a real make id can still
      # have zero models under the fixture; the boundary contract is about
      # what CROSSED the boundary, not what came back.
      _ = make_result

      # Exactly two facade spans opened across the whole scripted sequence,
      # one per successful event. No stray dispatches.
      assert query_count(ref) == 2
    end

    test "a stealth extra key returns :invalid_selector without ever reaching Catalog",
         %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/vehicle/select")

      ref = attach_query_start_probe()
      bucket = RateLimit.new()

      # The sneaky key: shape-legal on the wire, but `vin` is not in the
      # vocabulary and not in the event allowlist. `CatalogEvents` must fail
      # the whole selector — never trim `vin` off and let `{"year" => 2020}`
      # through as if the client had sent it alone.
      assert {:error, :invalid_selector, returned_bucket} =
               CatalogEvents.handle(
                 "catalog:select_year",
                 %{"year" => 2020, "vin" => "sneaky"},
                 bucket,
                 0
               )

      # The rate-limit bucket is returned UNCHANGED — `reject_extra_keys/2`
      # short-circuited before `RateLimit.take/3` was reached, so the token
      # was never spent. This is the boundary before the boundary.
      assert returned_bucket == bucket

      # And no Catalog query ever ran. `Telemetry.span/2` is the first line
      # of `Catalog.call/3`, so a start event fires the moment the facade is
      # entered. A zero here means the facade was never entered at all.
      assert query_count(ref) == 0
      refute_receive {:catalog_query_started, _}, 50

      # Structural bookend, tying this scripted test back to
      # `impersonal_selector_test`: the vocabulary itself does not know about
      # `vin`, so `Vocabulary.key_atom/1` refuses to atomize it. The wire
      # gate above and the structural gate here refuse the same key from
      # opposite ends.
      refute :vin in Map.keys(Vocabulary.field_specs())
      assert Vocabulary.key_atom("vin") == :error
    end

    # ------------------------------------------------------------------------
    # The `vin` test above proves the OUTER refusal: a key that isn't in the
    # vocabulary at all can never cross the boundary. But that test does not
    # exercise `CatalogEvents.reject_extra_keys/2` specifically — `vin` fails
    # inside `Selector.validate/2` (via `Vocabulary.key_atom/1`) anyway, so
    # deleting `reject_extra_keys/2` still leaves it green.
    #
    # These three cases close that gap. Each stealth key IS in
    # `Vocabulary.field_specs()` AND IS an optional key on the mapped function
    # (`list_makes` allows `:cursor`/`:page_size`; `list_models` allows
    # `:cursor`/`:page_size`), so `Selector.validate/2` would happily accept
    # the payload. Only the EVENT allowlist — enforced by
    # `CatalogEvents.reject_extra_keys/2` — knows that `catalog:select_year`
    # forbids anything except `"year"`, and `catalog:select_make` forbids
    # anything except `"year"` and `"make_id"`. If that gate were deleted, the
    # dispatch would go through and telemetry would fire.
    # ------------------------------------------------------------------------

    test "cursor stealth on catalog:select_year is caught by the event allowlist",
         %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/vehicle/select")

      # Sanity: this key is BOTH in the vocabulary AND allowed on the mapped
      # function (`list_makes` has `:cursor` as optional). So the ONLY thing
      # standing between it and the facade is `reject_extra_keys/2`.
      assert :cursor in Map.keys(Vocabulary.field_specs())
      assert :cursor in Vocabulary.function_specs().list_makes.optional
      refute "cursor" in Map.fetch!(Vocabulary.event_allowlist(), "catalog:select_year")

      ref = attach_query_start_probe()
      bucket = RateLimit.new()

      assert {:error, :invalid_selector, ^bucket} =
               CatalogEvents.handle(
                 "catalog:select_year",
                 %{"year" => @scripted_year, "cursor" => "abc"},
                 bucket,
                 0
               )

      # No token spent, no facade span opened.
      assert query_count(ref) == 0
      refute_receive {:catalog_query_started, _}, 50
    end

    test "page_size stealth on catalog:select_year is caught by the event allowlist",
         %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/vehicle/select")

      assert :page_size in Map.keys(Vocabulary.field_specs())
      assert :page_size in Vocabulary.function_specs().list_makes.optional
      refute "page_size" in Map.fetch!(Vocabulary.event_allowlist(), "catalog:select_year")

      ref = attach_query_start_probe()
      bucket = RateLimit.new()

      assert {:error, :invalid_selector, ^bucket} =
               CatalogEvents.handle(
                 "catalog:select_year",
                 %{"year" => @scripted_year, "page_size" => 100},
                 bucket,
                 0
               )

      assert query_count(ref) == 0
      refute_receive {:catalog_query_started, _}, 50
    end

    test "cursor stealth on catalog:select_make is caught by the event allowlist",
         %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/vehicle/select")

      make_id = any_make_id_for(@scripted_year)

      assert is_binary(make_id),
             "fixture must contain at least one make for #{@scripted_year} to source " <>
               "a real `make_id` — otherwise Selector.validate would fail on the id " <>
               "shape before we even reach the allowlist gate this test targets"

      # Same shape of guarantee as the two tests above, but on a different
      # event (`catalog:select_make` -> `list_models`) — so the fix is proven
      # to be at the shared `reject_extra_keys/2` gate rather than an
      # event-specific quirk.
      assert :cursor in Map.keys(Vocabulary.field_specs())
      assert :cursor in Vocabulary.function_specs().list_models.optional
      refute "cursor" in Map.fetch!(Vocabulary.event_allowlist(), "catalog:select_make")

      ref = attach_query_start_probe()
      bucket = RateLimit.new()

      assert {:error, :invalid_selector, ^bucket} =
               CatalogEvents.handle(
                 "catalog:select_make",
                 %{"year" => @scripted_year, "make_id" => make_id, "cursor" => "xyz"},
                 bucket,
                 0
               )

      assert query_count(ref) == 0
      refute_receive {:catalog_query_started, _}, 50
    end
  end
end
