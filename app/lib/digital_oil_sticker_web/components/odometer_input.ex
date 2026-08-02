defmodule DigitalOilStickerWeb.Components.OdometerInput do
  @moduledoc """
  Odometer entry: numeric text input + unit select. The canonical value is
  integer metres (DigitalOilSticker.Units); the original typed value and
  unit are stored alongside so rounding is always recoverable. Switching the
  unit re-labels — it never re-converts the typed value.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :value, :string, default: nil
  attr :unit, :string, default: "mi"
  attr :errors, :list, default: []

  def odometer_input(assigns) do
    ~H"""
    <div>
      <label for={@id} class="mb-1 block text-sm font-semibold">Odometer</label>
      <div class="flex gap-2">
        <input
          type="text"
          inputmode="numeric"
          pattern="[0-9,\s]*"
          id={@id}
          name="odometer[value]"
          value={@value}
          autocomplete="off"
          class="w-full min-h-11 rounded border px-3 py-2"
          aria-describedby={"#{@id}-error"}
        />
        <select
          id={"#{@id}-unit"}
          name="odometer[unit]"
          class="min-h-11 rounded border px-2"
          aria-label="Odometer unit"
        >
          {Phoenix.HTML.Form.options_for_select([{"mi", "mi"}, {"km", "km"}], @unit)}
        </select>
      </div>
      <p :if={@errors != []} id={"#{@id}-error"} role="alert" class="mt-1 text-sm text-error">
        {Enum.join(@errors, " ")}
      </p>
    </div>
    """
  end
end
