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

## Design history (do not use in production)

`assets/brand/drafts/` retains the superseded iterations: the original orange-drop/teal-gauge badge (`logo-original-badge.png`), the first checkered-form SVG (`logo-form-v1.svg`), badge SVG drafts, and the earlier compact mark. The teal/amber concept is design history only.

DOS-M02-002 (design system) owns final contrast-checked tokens and any further icon/splash exports.
