defmodule DigitalOilSticker.Catalog.CrossLevelTest do
  @moduledoc """
  DOS-M09-004 AC-4: cross-level closed-set behaviour.

  AC-4's clause under test: a child selector value that was NOT drawn from the
  prior level's response must be rejected rather than answered.

  The selector layer accepts any string that matches the `catalog_id` regex
  (`^[a-z0-9-]{1,64}$`), so a well-formed but fabricated `make_id` or
  `model_id` clears `Selector.validate/2`. Enforcement of the "must have come
  from the prior level" clause therefore has to land at the query layer.

  This test pins the STRONG form of the AC-4 clause the facade emits today:

    * `Catalog.list_models/1` with an unknown-but-well-formed `make_id` and
    * `Catalog.list_configurations/1` with an unknown-but-well-formed
      `make_id` or `model_id`

  both return `{:ok, %Result{status: :unsupported, data: []}}` carrying the
  `%{code: :parent_not_in_cascade}` qualifier — the caller can tell "the
  parent id was fabricated" apart from "the parent was real but no children
  exist for it." The parent-existence check runs before the identity query so
  a fabricated id never touches the join.

  The `:identity_only` + `[]` shape stays reserved for a real parent with a
  genuinely empty child set (a case the current fixture can't produce, since
  `list_makes/list_models` already join through `vehicle_configurations` — but
  it remains the correct answer if the schema ever allows it).
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{Result, Selector}

  # Well-formed under `^[a-z0-9-]{1,64}$`, not present in fixture-a.
  @unknown_make_id "not-a-real-make-000"
  @unknown_model_id "not-a-real-model-000"

  test "list_models with an unknown make_id returns :unsupported with :parent_not_in_cascade" do
    {:ok, sel} =
      Selector.validate(:list_models, %{"year" => 2024, "make_id" => @unknown_make_id})

    assert {:ok,
            %Result{
              status: :unsupported,
              data: [],
              total: 0,
              total_known?: true,
              cursor: nil
            } = result} = Catalog.list_models(sel)

    assert Enum.any?(result.qualifiers, &(&1.code == :parent_not_in_cascade)),
           "unknown make_id must be flagged with :parent_not_in_cascade so callers " <>
             "can distinguish a fabricated parent from a real parent with no children"
  end

  test "list_configurations with an unknown model_id returns :unsupported with :parent_not_in_cascade" do
    # Anchor the unknown model_id under a real (year, make_id) so only the
    # model_id is the cross-level fabrication under test.
    {:ok, makes_sel} = Selector.validate(:list_makes, %{"year" => 2024})
    {:ok, makes} = Catalog.list_makes(makes_sel)
    toyota = Enum.find(makes.data, &(&1.normalized_name == "toyota"))
    assert toyota, "fixture must contain Toyota for 2024"

    {:ok, sel} =
      Selector.validate(:list_configurations, %{
        "year" => 2024,
        "make_id" => toyota.id,
        "model_id" => @unknown_model_id
      })

    assert {:ok,
            %Result{
              status: :unsupported,
              data: [],
              cursor: nil
            } = result} = Catalog.list_configurations(sel)

    assert Enum.any?(result.qualifiers, &(&1.code == :parent_not_in_cascade))
  end

  test "list_configurations with an unknown make_id (before model_id checked) is also :unsupported" do
    # The make_id is fabricated, so the model_id lookup never happens — the
    # short-circuit on the higher parent is what the caller sees.
    {:ok, sel} =
      Selector.validate(:list_configurations, %{
        "year" => 2024,
        "make_id" => @unknown_make_id,
        "model_id" => "any-well-formed-id"
      })

    assert {:ok,
            %Result{
              status: :unsupported,
              data: [],
              cursor: nil
            } = result} = Catalog.list_configurations(sel)

    assert Enum.any?(result.qualifiers, &(&1.code == :parent_not_in_cascade))
  end

  test "the fabricated ids used above really are well-formed selector inputs" do
    # Regression guard for the moduledoc's premise: if the id regex tightens
    # so these strings stop validating, the two cases above stop being
    # cross-level fabrications and start being selector-level rejections —
    # which is a different AC-4 claim and would need a different test.
    assert {:ok, _} =
             Selector.validate(:list_models, %{
               "year" => 2024,
               "make_id" => @unknown_make_id
             })

    assert {:ok, _} =
             Selector.validate(:list_configurations, %{
               "year" => 2024,
               "make_id" => "toyota",
               "model_id" => @unknown_model_id
             })
  end
end
