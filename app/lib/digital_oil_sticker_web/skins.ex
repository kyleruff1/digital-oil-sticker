defmodule DigitalOilStickerWeb.Skins do
  @moduledoc """
  The sticker skin vocabulary: six owner-approved re-skins of the sticker
  artwork, applied through CSS custom properties scoped by a `data-skin`
  attribute on the garage layout (see `assets/css/app.css`).

  ## Why this module exists

  Three surfaces have to agree on what a skin is — the CSS token blocks, the
  picker on `/`, and the pref value stored in the browser — and they drift the
  moment each keeps its own list. The slugs live here; the others read them.

  ## The fallback rule

  `from_prefs/1` maps anything that is not a known slug — nil, an empty map, a
  value written by a newer release with more skins — to the default. Same
  philosophy as the dangling `active_vehicle_id` handling in
  `LocalStore.Session`: silent render-time fallback, no quarantine, no repair,
  no write-back. A cosmetic preference must never make stored data unreadable.

  ## The default is the locked brand contract

  `service-bay` has no CSS override block at all — the token defaults on
  `.dos-sticker-frame` ARE the locked palette from `docs/product/BRAND.md`,
  which is what keeps the default pixel-identical to the pre-skin rendering
  (proven by `sticker_art_parity_test.exs`).
  """

  @slugs ~w(service-bay midnight-shift blueprint vintage-pump track-day brushed-steel)

  @default "service-bay"

  # The browser-chrome accent (`theme-color` meta) each skin carries. The
  # light-theme page accent, not the sticker body: browser chrome sits next
  # to the OS UI, where the accent reads as the app's identity color.
  @accents %{
    "service-bay" => "#159447",
    "midnight-shift" => "#3DDC84",
    "blueprint" => "#1D4E89",
    "vintage-pump" => "#8C2B2E",
    "track-day" => "#C8102E",
    "brushed-steel" => "#1E5C8F"
  }

  @doc "Every skin slug, in picker display order. The first is the default."
  @spec slugs() :: [String.t()]
  def slugs, do: @slugs

  @doc "The default skin — the live look, the locked brand contract."
  @spec default() :: String.t()
  def default, do: @default

  @doc """
  The skin a prefs map selects, with unknown/missing values falling back to
  the default. Nil-safe: hydration failures hand `Session` a nil prefs
  singleton, and this must not add a second failure mode on top.
  """
  @spec from_prefs(map() | nil) :: String.t()
  def from_prefs(%{"sticker_skin" => slug}) when slug in @slugs, do: slug
  def from_prefs(_), do: @default

  @doc "The browser-chrome accent hex for a skin (theme-color meta)."
  @spec accent(String.t() | nil) :: String.t()
  def accent(slug) when is_binary(slug), do: Map.get(@accents, slug, @accents[@default])
  def accent(_), do: @accents[@default]
end
