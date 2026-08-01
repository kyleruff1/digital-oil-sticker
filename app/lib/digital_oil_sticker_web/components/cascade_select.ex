defmodule DigitalOilStickerWeb.Components.CascadeSelect do
  @moduledoc """
  One level of the year→make→model→build cascade. Server-driven via
  phx-change on the wrapping form; per-level states disabled / loading /
  populated / narrowed_empty / cleared. Unknown attribute values render
  "Not specified" — never guessed. 44×44 minimum targets; result counts are
  announced by a separate polite live region without moving focus.
  """
  use Phoenix.Component
  alias DigitalOilStickerWeb.Copy

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, default: [], doc: "{value, label} tuples"
  attr :value, :any, default: nil
  attr :state, :atom, values: [:disabled, :loading, :populated, :narrowed_empty], required: true
  attr :upstream_label, :string, default: nil
  attr :prompt, :string, default: "Choose…"

  def cascade_select(assigns) do
    ~H"""
    <div class="min-w-0">
      <label for={@id} class="mb-1 block text-sm font-semibold">{@label}</label>
      <select
        id={@id}
        name={@name}
        disabled={@state in [:disabled, :loading]}
        aria-disabled={to_string(@state in [:disabled, :loading])}
        aria-busy={to_string(@state == :loading)}
        aria-describedby={"#{@id}-hint"}
        class="w-full min-h-11 rounded border px-2 py-2"
      >
        <option value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <p id={"#{@id}-hint"} class="mt-1 min-h-5 text-xs text-zinc-500">
        <span :if={@state == :disabled and @upstream_label}>{Copy.choose_upstream(@upstream_label)}</span>
        <span :if={@state == :loading}>{Copy.loading()}</span>
        <span :if={@state == :narrowed_empty}>
          {Copy.narrowed_empty(@label, @upstream_label || "previous choice")}
        </span>
      </p>
    </div>
    """
  end
end
