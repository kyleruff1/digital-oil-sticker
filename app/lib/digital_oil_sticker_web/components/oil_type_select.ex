defmodule DigitalOilStickerWeb.Components.OilTypeSelect do
  @moduledoc """
  What kind of oil went in: base stock (conventional / blend / full synthetic /
  high mileage) plus a viscosity grade.

  Brand is deliberately absent. Products from different brands share the same
  chemistry, so a brand list produced many entries meaning the same thing and
  no fact the app could stand behind. Base stock and grade are what actually
  move the interval, and both come from our own model.

  The grade list is filtered to the grades typical for the vehicle's engine
  class, with every other grade we list one control away and a free-text entry
  after that — the user can always record what they actually used.
  """
  use Phoenix.Component

  alias DigitalOilStickerWeb.Copy

  attr :base_stocks, :list, required: true
  attr :base_stock, :string, default: nil
  attr :suggested_grades, :list, default: []
  attr :other_grades, :list, default: []
  attr :grade, :string, default: nil
  attr :show_all_grades?, :boolean, default: false
  attr :manual_grade?, :boolean, default: false
  attr :manual_grade, :string, default: nil
  attr :engine_class_name, :string, default: nil

  def oil_type_select(assigns) do
    ~H"""
    <div class="space-y-4">
      <fieldset>
        <legend class="mb-1 block text-sm font-semibold">Type of oil</legend>
        <div class="grid gap-2 sm:grid-cols-2">
          <label
            :for={stock <- @base_stocks}
            class={[
              "flex min-h-11 cursor-pointer items-start gap-2 rounded border px-3 py-2",
              @base_stock == stock.code && "border-2 border-emerald-700"
            ]}
          >
            <input
              type="radio"
              name="oil[base_stock]"
              value={stock.code}
              checked={@base_stock == stock.code}
              class="mt-1"
            />
            <span>
              <span class="block text-sm font-semibold">{stock.display_name}</span>
              <span class="block text-xs text-zinc-500">
                {Copy.miles_range(stock.published_miles_low, stock.published_miles_high)}
              </span>
            </span>
          </label>
        </div>
      </fieldset>

      <div>
        <label for="oil-grade" class="mb-1 block text-sm font-semibold">Grade (viscosity)</label>

        <select
          :if={not @manual_grade?}
          id="oil-grade"
          name="oil[grade]"
          class="w-full min-h-11 rounded border px-2 py-2"
        >
          <option value="">Choose…</option>
          <optgroup :if={@suggested_grades != []} label={suggested_label(@engine_class_name)}>
            {Phoenix.HTML.Form.options_for_select(Enum.map(@suggested_grades, &{&1.code, &1.code}), @grade)}
          </optgroup>
          <optgroup :if={@show_all_grades? and @other_grades != []} label="Every other grade we list">
            {Phoenix.HTML.Form.options_for_select(Enum.map(@other_grades, &{&1.code, &1.code}), @grade)}
          </optgroup>
          <option value="__all__">{Copy.grade_show_all()}</option>
          <option value="__manual__">{Copy.grade_not_listed()}</option>
        </select>

        <div :if={@manual_grade?}>
          <input
            type="text"
            id="oil-grade"
            name="oil[manual_grade]"
            value={@manual_grade}
            placeholder="e.g. 5W-30"
            maxlength="20"
            class="w-full min-h-11 rounded border px-3 py-2"
          />
          <p class="mt-1 text-xs text-zinc-500">{Copy.user_entered()}</p>
        </div>

        <p :if={grade_note(@suggested_grades, @grade)} class="mt-1 text-xs text-zinc-500">
          {grade_note(@suggested_grades, @grade)}
        </p>
      </div>
    </div>
    """
  end

  defp suggested_label(nil), do: "Commonly used grades"
  defp suggested_label(class_name), do: Copy.grade_suggested_for(class_name)

  defp grade_note(_suggested, nil), do: nil

  defp grade_note(suggested, code) do
    case Enum.find(suggested, &(&1.code == code)) do
      %{notes: notes} when is_binary(notes) -> notes
      _ -> nil
    end
  end
end
