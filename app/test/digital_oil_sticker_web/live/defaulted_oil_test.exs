defmodule DigitalOilStickerWeb.DefaultedOilTest do
  @moduledoc """
  The "defaulted vs selected" oil distinction — the critical fix for the
  intake-defaults change.

  Before this distinction existed, the picker's app-chosen full-synthetic
  default rode as `planned_oil: "selected"` into the vehicle plan, and the
  log form's pre-fill absorbed the pre-checked radio into `oil_base_stock`
  whenever the user just typed the date or the odometer — so the app's
  assumption ended up saved as a first-person record of what actually went
  in the crankcase.

  Now: `planned_oil: "defaulted"` marks an app-chosen plan. Downstream:

    * The sticker qualifier reads it and says "assuming X" instead of
      attributing the number to the user's answer.
    * The log form does NOT pre-fill from a defaulted plan, so a save without
      touching the oil section writes `oil_base_stock: nil` — an honest
      "we do not know" — rather than the app's default masquerading as fact.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  @vehicle_id "11111111-1111-4111-8111-111111111111"

  defp vehicle(plan) do
    %{
      "vehicle_id" => @vehicle_id,
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "LE"
      },
      "engine_class_code" => "gas_direct_injection",
      "maintenance_plan" => plan
    }
  end

  defp hydrate(view, data) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 1,
      "tab_id" => "t",
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
          data
        ),
      "storage" => %{"mode" => "idb", "boot_hint" => "never"}
    })
  end

  describe "the sticker qualifier" do
    test "a defaulted plan reads as \"assuming\" — never attributed to the user", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # No event yet — a fresh vehicle whose intake was defaulted. The sticker
      # renders no due estimate without a logged change, so we skip past that
      # by pre-loading a plan with a user interval AND a defaulted oil, and
      # a logged change with no oil recorded. The interval math still runs;
      # what we're asserting is the LABEL on the number.
      html =
        hydrate(view, %{
          "vehicles" => [
            vehicle(%{
              "planned_oil" => "defaulted",
              "planned_base_stock" => "full_synthetic",
              "planned_grade" => "5W-30"
            })
          ],
          "events" => [
            %{
              "event_id" => "22222222-2222-4222-8222-222222222222",
              "vehicle_id" => @vehicle_id,
              "performed_at" => "2026-06-15",
              "odometer_m" => 80_467_200,
              "input_unit" => "mi",
              "provenance_mode" => "manual"
            }
          ]
        })

      # "assuming" clause is present, and the "based on Your interval" and
      # "Our estimate, not manufacturer guidance" clauses that would falsely
      # credit the user are NOT.
      assert html =~ "assuming full synthetic"
      refute html =~ "based on Your interval"
    end

    test "a defaulted plan with a user-set months-only interval still says \"assuming\"", %{
      conn: conn
    } do
      # Reachable state: intake defaulted; user set only interval_months on
      # the vehicle page; user logs a change without picking oil. The user's
      # 6-month cap wins over the model's 12-month cap; the model still
      # supplies the miles ceiling from the ASSUMED full-synthetic rule.
      # basis resolves to :mixed. Without the :mixed clause on
      # :planned_default, this state dropped the "assuming" caveat entirely.
      {:ok, view, _} = live(conn, ~p"/")

      html =
        hydrate(view, %{
          "vehicles" => [
            vehicle(%{
              "planned_oil" => "defaulted",
              "planned_base_stock" => "full_synthetic",
              "planned_grade" => "5W-30",
              "interval_months" => 6
            })
          ],
          "events" => [
            %{
              "event_id" => "22222222-2222-4222-8222-222222222222",
              "vehicle_id" => @vehicle_id,
              "performed_at" => "2026-06-15",
              "odometer_m" => 80_467_200,
              "input_unit" => "mi",
              "provenance_mode" => "manual"
            }
          ]
        })

      assert html =~ "assuming full synthetic"
    end

    test "a selected plan still reads with the plain \"Our estimate\" attribution", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      html =
        hydrate(view, %{
          "vehicles" => [
            vehicle(%{
              "planned_oil" => "selected",
              "planned_base_stock" => "full_synthetic",
              "planned_grade" => "5W-30"
            })
          ],
          "events" => [
            %{
              "event_id" => "22222222-2222-4222-8222-222222222222",
              "vehicle_id" => @vehicle_id,
              "performed_at" => "2026-06-15",
              "odometer_m" => 80_467_200,
              "input_unit" => "mi",
              "provenance_mode" => "manual"
            }
          ]
        })

      # Explicitly NOT the assumption clause — the user chose this oil.
      refute html =~ "assuming full synthetic"
      assert html =~ "Our estimate"
    end
  end

  describe "the vehicle profile page" do
    test "shows the assumed-oil note when the plan is defaulted", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle")

      html =
        hydrate(view, %{
          "vehicles" => [
            vehicle(%{
              "planned_oil" => "defaulted",
              "planned_base_stock" => "full_synthetic",
              "planned_grade" => "5W-30"
            })
          ],
          "prefs" => %{"active_vehicle_id" => @vehicle_id}
        })

      # Same "assuming" note the sticker shows, on the page a user goes to
      # precisely to inspect and change their vehicle's assumptions.
      assert html =~ "assuming full synthetic"
    end

    test "does NOT show the assumed-oil note for a selected plan", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle")

      html =
        hydrate(view, %{
          "vehicles" => [
            vehicle(%{
              "planned_oil" => "selected",
              "planned_base_stock" => "full_synthetic",
              "planned_grade" => "5W-30"
            })
          ],
          "prefs" => %{"active_vehicle_id" => @vehicle_id}
        })

      refute html =~ "assuming full synthetic"
    end
  end

  describe "the log form's pre-fill" do
    defp log_hydrate(view, plan) do
      hydrate(view, %{
        "vehicles" => [vehicle(plan)],
        "prefs" => %{"active_vehicle_id" => @vehicle_id}
      })
    end

    test "pre-fills from a SELECTED plan, so a save records the user's answer", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      log_hydrate(view, %{
        "planned_oil" => "selected",
        "planned_base_stock" => "full_synthetic",
        "planned_grade" => "5W-30"
      })

      # User fills date + odometer, never touches the oil section, saves.
      render_change(view, "form_change", %{
        "service_date" => %{"month" => "6", "day" => "15", "year" => "2026"},
        "odometer" => %{"value" => "50000", "unit" => "mi"},
        "oil" => %{"base_stock" => "full_synthetic", "grade" => "5W-30"},
        "notes" => ""
      })

      render_submit(view, "submit", %{})
      assert_push_event(view, "local_store:put", payload)

      event = payload["upserts"] |> Enum.find(&(&1["store"] == "events")) |> Map.fetch!("record")

      # Selected → the user's stated oil is the record.
      assert event["oil_base_stock"] == "full_synthetic"
      assert event["oil_viscosity"] == "5W-30"
    end

    test "does NOT pre-fill from a DEFAULTED plan — a save without touching writes nil oil", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/service/new")

      log_hydrate(view, %{
        "planned_oil" => "defaulted",
        "planned_base_stock" => "full_synthetic",
        "planned_grade" => "5W-30"
      })

      # A phx-change on the whole form will still ship the pre-checked radio's
      # value if one is checked. The pre-fill helper's job is to make sure no
      # radio IS pre-checked when the plan is defaulted, so the params here
      # carry an empty base_stock.
      render_change(view, "form_change", %{
        "service_date" => %{"month" => "6", "day" => "15", "year" => "2026"},
        "odometer" => %{"value" => "50000", "unit" => "mi"},
        "oil" => %{"base_stock" => "", "grade" => ""},
        "notes" => ""
      })

      render_submit(view, "submit", %{})
      assert_push_event(view, "local_store:put", payload)

      event = payload["upserts"] |> Enum.find(&(&1["store"] == "events")) |> Map.fetch!("record")

      # Defaulted → the record is honest: we do not know what went in, because
      # the user never told us.
      assert event["oil_base_stock"] == nil
      assert event["oil_viscosity"] == nil
    end

    test "the RENDERED form does not pre-check a radio for a defaulted plan", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        log_hydrate(view, %{
          "planned_oil" => "defaulted",
          "planned_base_stock" => "full_synthetic",
          "planned_grade" => "5W-30"
        })

      refute html =~ ~s(value="full_synthetic" checked)
      refute html =~ ~s(<option selected value="5W-30">)
    end

    test "the RENDERED form DOES pre-check a radio for a selected plan", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        log_hydrate(view, %{
          "planned_oil" => "selected",
          "planned_base_stock" => "full_synthetic",
          "planned_grade" => "5W-30"
        })

      assert html =~ ~s(value="full_synthetic" checked)
    end

    test "shows a needs-oil banner when the intake was defaulted, hides it after selection", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        log_hydrate(view, %{
          "planned_oil" => "defaulted",
          "planned_base_stock" => "full_synthetic",
          "planned_grade" => "5W-30"
        })

      assert html =~ "data-test=\"log-form-needs-oil\""
      assert html =~ "No oil type was recorded at intake"

      # Once the user picks something, the banner should be gone — the state
      # it existed to distinguish (unrecorded vs cleared) is no longer
      # ambiguous.
      html =
        render_change(view, "form_change", %{
          "service_date" => %{"month" => "", "day" => "", "year" => ""},
          "odometer" => %{"value" => "", "unit" => "mi"},
          "oil" => %{"base_stock" => "conventional", "grade" => ""},
          "notes" => ""
        })

      refute html =~ "data-test=\"log-form-needs-oil\""
    end

    test "no needs-oil banner for a selected plan", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        log_hydrate(view, %{
          "planned_oil" => "selected",
          "planned_base_stock" => "full_synthetic",
          "planned_grade" => "5W-30"
        })

      refute html =~ "data-test=\"log-form-needs-oil\""
    end

    test "shows a distinct banner for an unknown-at-intake plan", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html = log_hydrate(view, %{"planned_oil" => "unknown"})

      # Banner is present…
      assert html =~ "data-test=\"log-form-needs-oil\""
      # …with the unknown-specific copy, not the "no oil was recorded" copy
      # that would lie about what intake stored.
      assert html =~ "You said you didn&#39;t know the oil type at intake"
      refute html =~ "No oil type was recorded at intake"
      # And a machine-readable marker for which kind fired.
      assert html =~ ~s(data-prompt-kind="unknown")
    end

    test "the defaulted banner carries its own kind marker", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        log_hydrate(view, %{
          "planned_oil" => "defaulted",
          "planned_base_stock" => "full_synthetic",
          "planned_grade" => "5W-30"
        })

      assert html =~ ~s(data-prompt-kind="defaulted")
      assert html =~ "No oil type was recorded at intake"
      refute html =~ "You said you didn&#39;t know"
    end
  end

  describe "the picker's touch tracking" do
    defp cascade_to_confirm(view) do
      row =
        DigitalOilSticker.CatalogRepo.one(
          from(c in "vehicle_configurations",
            select: %{
              key: c.configuration_key,
              year: c.model_year,
              make_id: c.make_id,
              model_id: c.model_id
            },
            where: not is_nil(c.engine_class_code),
            limit: 1
          )
        )

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

      render_change(view, "cascade_change", %{"year" => to_string(row.year)})

      render_change(view, "cascade_change", %{
        "year" => to_string(row.year),
        "make_id" => row.make_id
      })

      render_change(view, "cascade_change", %{
        "year" => to_string(row.year),
        "make_id" => row.make_id,
        "model_id" => row.model_id
      })

      render_change(view, "cascade_change", %{
        "year" => to_string(row.year),
        "make_id" => row.make_id,
        "model_id" => row.model_id,
        "configuration_key" => row.key
      })
    end

    test "confirming without touching oil writes planned_oil=defaulted", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      cascade_to_confirm(view)

      render_click(view, "confirm", %{})
      assert_push_event(view, "local_store:put", payload)

      vehicle =
        payload["upserts"] |> Enum.find(&(&1["store"] == "vehicles")) |> Map.fetch!("record")

      assert vehicle["maintenance_plan"]["planned_oil"] == "defaulted"
      assert vehicle["maintenance_plan"]["planned_base_stock"] == "full_synthetic"
    end

    test "a single interaction with the oil form flips planned_oil to selected", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      cascade_to_confirm(view)

      # Any oil-form change is a user interaction — even re-affirming the
      # defaulted value. The user opened this control and made a choice about
      # what to leave in.
      render_change(view, "oil_change", %{
        "oil" => %{"base_stock" => "full_synthetic", "grade" => ""}
      })

      render_click(view, "confirm", %{})
      assert_push_event(view, "local_store:put", payload)

      vehicle =
        payload["upserts"] |> Enum.find(&(&1["store"] == "vehicles")) |> Map.fetch!("record")

      assert vehicle["maintenance_plan"]["planned_oil"] == "selected"
    end

    test "the intake recommendation panel is announced to screen readers", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      cascade_to_confirm(view)

      html = render(view)

      # role=status + aria-live=polite: when the user arrows through the
      # base-stock radios and the recommendation number recomputes, screen
      # readers hear it. Before this attr existed, the calculated number
      # updated silently for non-sighted users.
      assert html =~ ~s(data-test="intake-recommendation")
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-live="polite")
    end
  end
end
