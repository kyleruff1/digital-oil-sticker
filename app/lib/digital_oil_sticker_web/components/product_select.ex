defmodule DigitalOilStickerWeb.Components.ProductSelect do
  @moduledoc """
  Oil brand → family dependent selects, backed by the catalog's BROWSING
  path (plain-text identification; no compatibility meaning — rev-2 policy
  splits browsing from fitment). "Not listed — enter it myself" is always
  present and reveals user-entered fields tagged manual. When the oil list
  is gated off entirely, the selects are absent — only the user-entered
  fields render.
  """
  use Phoenix.Component
  alias DigitalOilStickerWeb.Components.Badges
  alias DigitalOilStickerWeb.Copy

  attr :brands, :list, default: [], doc: "catalog brand rows (may be empty when gated)"
  attr :families, :list, default: []
  attr :brand_id, :string, default: nil
  attr :family_id, :string, default: nil
  attr :manual?, :boolean, default: false
  attr :manual_brand, :string, default: nil
  attr :manual_family, :string, default: nil
  attr :observed_at, :string, default: nil

  def product_select(assigns) do
    ~H"""
    <div class="space-y-2">
      <div :if={@brands != []} class="grid grid-cols-2 gap-2">
        <div>
          <label for="oil-brand" class="mb-1 block text-sm font-semibold">Oil brand</label>
          <select id="oil-brand" name="oil[brand_id]" class="w-full min-h-11 rounded border px-2 py-2">
            <option value="">Choose…</option>
            {Phoenix.HTML.Form.options_for_select(Enum.map(@brands, &{&1.display_name, &1.id}), @brand_id)}
            <option value="__manual__" selected={@manual?}>{Copy.not_listed_enter_myself()}</option>
          </select>
        </div>
        <div>
          <label for="oil-family" class="mb-1 block text-sm font-semibold">Oil family</label>
          <select
            id="oil-family"
            name="oil[family_id]"
            disabled={is_nil(@brand_id) or @manual?}
            class="w-full min-h-11 rounded border px-2 py-2"
          >
            <option value="">Choose…</option>
            {Phoenix.HTML.Form.options_for_select(Enum.map(@families, &{&1.product_family, &1.id}), @family_id)}
          </select>
        </div>
      </div>

      <p :if={@brands != [] and @observed_at} class="text-xs text-zinc-500">
        {Copy.as_of(@observed_at)} <Badges.provenance_badge mode={:catalog} />
      </p>

      <div :if={@brands == [] or @manual?} class="grid grid-cols-2 gap-2">
        <div>
          <label for="oil-manual-brand" class="mb-1 block text-sm font-semibold">
            Oil brand <Badges.provenance_badge mode={:manual} />
          </label>
          <input
            type="text"
            id="oil-manual-brand"
            name="oil[manual_brand]"
            value={@manual_brand}
            maxlength="80"
            class="w-full min-h-11 rounded border px-3 py-2"
          />
        </div>
        <div>
          <label for="oil-manual-family" class="mb-1 block text-sm font-semibold">
            Oil family <Badges.provenance_badge mode={:manual} />
          </label>
          <input
            type="text"
            id="oil-manual-family"
            name="oil[manual_family]"
            value={@manual_family}
            maxlength="80"
            class="w-full min-h-11 rounded border px-3 py-2"
          />
        </div>
      </div>
    </div>
    """
  end
end
