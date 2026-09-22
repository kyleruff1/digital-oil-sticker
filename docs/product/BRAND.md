# Brand assets

## Canonical files (owner-adopted 2026-08-01 — supersedes all prior sets)

The superseding pack lives in `assets/brand/` with its own detailed contract in [`assets/brand/README.md`](../../assets/brand/README.md). Summary:

| Asset | File | Role |
| --- | --- | --- |
| Main logo (vector) | `assets/brand/logo.svg` | Canonical **translucent window-cling sticker frame** and company lockup ("Digital Oil Sticker — Next Service Due"): 72%-opacity cling body, crossed waving checkered flags, peel corner. Date/Mileage/Grade/OR value boxes are deliberately absent — **live HTML owns them** (viewport contract below). |
| Raster fallback | `assets/brand/logo.png` | 1320×640 transparent render of the SVG. |
| Compact mark | `assets/brand/mark.svg` | Symbol for favicons, launch artwork, app-icon production; the required substitute below 320 CSS px width. |
| Favicon | `assets/brand/favicon.svg` + `.ico` + 16/32 PNGs | **Retained from the prior set by owner decision (2026-08-01)** — byte-identical to the pack's favicon; do not swap. |
| Home-screen icons | `apple-touch-icon.png`, `android-chrome-192x192.png`, `android-chrome-512x512.png`, `site.webmanifest` | PWA/home-screen metadata (manifest icon paths rewritten to `/images/` in the app copy). |

Deployed copies: `app/priv/static/favicon.ico`, `app/priv/static/site.webmanifest`, `app/priv/static/images/dos-logo.svg`, `dos-mark.svg`, `dos-favicon.svg`, touch/chrome icons. Head block lives in `root.html.heex` (`theme-color #159447`).

## Color contract (locked)

| Role | Hex |
| --- | --- |
| Service green | `#159447` |
| Digital blue | `#1769AA` |
| Structural black | `#101820` |
| Outline/highlight white | `#F7FAF8` |
| Cling white | `#FFFFFF` at 72% body opacity |

## Live viewport contract (the sticker is the front page)

The home route renders `logo.svg` as the bottom layer of a `position: relative; aspect-ratio: 1320/640` component with accessible HTML overlays at these positions (percentages of the full canvas — never crop the transparent margin, never add a background color to the img or its wrapper):

| Viewport | Left | Top | Width | Height |
| --- | ---: | ---: | ---: | ---: |
| Date | 14.24% | 50.5% | 30.15% | 12% |
| Mileage | 55.61% | 50.5% | 30.15% | 12% |
| Grade | 38.03% | 72.0% | 23.94% | 8% |

`DATE`, `OR`, `MILEAGE`, `GRADE` labels and their values are HTML, not artwork. Full usage rules (clear space, no recolor/stretch, 320 px minimum, app-store icon caveat) are in `assets/brand/README.md`.

## Sticker skins (owner-approved 2026-09-21)

The sticker artwork is parametric: the deployed component
(`app/lib/digital_oil_sticker_web/components/sticker_art.ex`) is an inline-SVG
transcription of `logo.svg` whose paints resolve through CSS custom properties
(`--skin-*`, declared in `app/assets/css/app.css`). Six owner-approved skins
re-declare those tokens under a `data-skin` attribute; a picker on the front
page switches them, and the choice persists in the browser's prefs
(`sticker_skin`).

**Service Bay is the default and IS the locked contract above, pixel-identical
by construction**: the CSS token defaults are the locked palette, no override
block exists for the default skin, and `sticker_art_parity_test.exs` holds the
inline transcription element-for-element equal to `logo.svg` (which remains
the canonical reference). The locked color contract and the "no recolor"
usage rule in `assets/brand/README.md` are scoped to the DEFAULT skin's
artwork; the five variants below are the owner-approved exception, and they
never alter geometry, the wordmark, `NEXT SERVICE DUE`, or the viewport
contract — color, opacity, and accent only.

The five variants are opaque-bodied (the 72% cling translucency is part of
the default's identity, not theirs). Every HTML-text pairing is computed
≥ 4.5:1. Page accents re-tint `--color-primary` under the same `data-skin`
scope; the browser-chrome `theme-color` follows the skin's accent via the
`SkinChrome` hook. The scan page (`/s`) always renders the default.

| Skin | Body | Ink | Brand A | Brand B | Stamp | Accent (light / dark) |
| --- | --- | --- | --- | --- | --- | --- |
| Service Bay (default) | `#FFFFFF` @ 72% | `#101820` | `#159447` | `#1769AA` | `#159447` | `#159447` (static) |
| Midnight Shift | `#101820` | `#F7FAF8` | `#3DDC84` | `#4FB8FF` | `#3DDC84` | `#3DDC84`/`#101820` both |
| Blueprint | `#123C6B` | `#F7FAF8` | `#DCE9F7` | `#9FC4E8` | `#FFFFFF` | `#1D4E89`/`#FFFFFF` · `#8FBCE8`/`#0E2B4F` |
| Vintage Pump | `#F5E9CF` | `#402A1E` | `#8C2B2E` | `#B4690E` | `#7A2024` | `#8C2B2E`/`#FFFFFF` · `#E8A94F`/`#2B1608` |
| Track Day | `#FFFFFF` | `#14181D` | `#C8102E` | `#4A525C` | `#C8102E` | `#C8102E`/`#FFFFFF` both |
| Brushed Steel | `#D7DBDE` | `#1F262B` | `#1E5C8F` | `#4A5560` | `#1E5C8F` | `#1E5C8F`/`#FFFFFF` · `#7FB3DC`/`#0F1B24` |

Full per-token values (edge, halo, checkers, skeleton, underline) live in the
skin blocks of `app/assets/css/app.css` — the single source the app reads.

## Design history (do not use in production)

`assets/brand/drafts/` retains the superseded iterations: the original orange-drop/teal-gauge badge (`logo-original-badge.png`), the first checkered-form SVG (`logo-form-v1.svg`), badge SVG drafts, and the earlier compact mark. The teal/amber concept is design history only.

DOS-M02-002 (design system) owns final contrast-checked tokens and any further icon/splash exports.
