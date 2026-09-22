# Digital Oil Sticker brand assets

The approved canonical main logo is `digital-oil-sticker-logo.svg`. It preserves the approved form artwork while adding the required window-cling transparency contract.

## Primary assets

- `digital-oil-sticker-logo.svg`: canonical translucent sticker frame and company lockup. It includes `NEXT SERVICE DUE`, two crossed strongly-waving checkered flags on short pole stubs, and a decorative peel corner. Date, Mileage, Grade, OR, and their value boxes are deliberately absent because live HTML owns them.
- `digital-oil-sticker-logo.png`: 1320×640 transparent raster fallback rendered from the primary SVG.
- `digital-oil-sticker-mark.svg`: compact symbol for favicons, launch artwork, and later app-icon production.
- `favicon.svg` and `favicon.ico`: scalable and legacy browser favicons.
- `favicon-16x16.png` and `favicon-32x32.png`: explicit browser PNG fallbacks.
- `apple-touch-icon.png`: 180px Apple home-screen icon.
- `android-chrome-192x192.png` and `android-chrome-512x512.png`: manifest icons.
- `site.webmanifest`: web-icon metadata with the locked brand colors.
- `digital-oil-sticker-logo-concept.png`: superseded teal/amber exploration retained only as design history; do not use it in production.

## Color contract

| Role | Hex |
| --- | --- |
| Service green | `#159447` |
| Digital blue | `#1769AA` |
| Structural black | `#101820` |
| Outline/highlight white | `#F7FAF8` |
| Cling white | `#FFFFFF` at 72% body opacity |

Keep clear space equal to at least one large pixel-square width. Do not remove or rewrite `NEXT SERVICE DUE`, recolor individual elements, alter the approved green/white/blue shading, or stretch the artwork — these prohibitions apply to the DEFAULT skin's artwork; the owner-approved skin variants (see the "Sticker skins" annex in `docs/product/BRAND.md`, adopted 2026-09-21) re-color through the CSS token system only and never alter geometry, the wordmark, or the heading. Do not place the full sticker lockup below 320 CSS pixels wide; at smaller sizes, use the compact mark.

The SVG canvas is fully transparent outside the sticker shape, and the white cling body is intentionally 72% opaque. This allows moving car-window imagery to remain visible beneath the form. Structural black uses a near-white outline/halo so it remains legible over both light and dark motion; green and blue retain near-white shading. Live input/viewports are separate DOM elements, not artwork embedded in the SVG. Before app-store submission, produce platform-specific icon exports with the required opaque backgrounds and safe zones; do not submit this transparent master directly as an iOS app icon.

The main logo's black core border, near-white halo, and green/blue inner keyline are substantially inset from the SVG canvas. At the canonical 1320×640 render, visible artwork begins 81 pixels inside every edge, leaving a real alpha-transparent margin outside the border and peel corner. Do not crop, fill, flatten, or remove this margin in site exports.

When displayed over an animated or video-backed car-window scene, the consuming element must also remain transparent: do not add a CSS background color to the `<img>`, `<object>`, or its immediate wrapper.

## Live viewport contract

Use the SVG as the bottom layer of a `position: relative` component with `aspect-ratio: 1320 / 640`. Place accessible HTML viewports above it. These percentages preserve the intended layout while allowing responsive scaling:

| Viewport | Left | Top | Width | Suggested height |
| --- | ---: | ---: | ---: | ---: |
| Date | `14.24%` | `50.5%` | `30.15%` | `12%` |
| Mileage | `55.61%` | `50.5%` | `30.15%` | `12%` |
| Grade | `38.03%` | `72.0%` | `23.94%` | `8%` |

Render the visible `DATE`, `OR`, `MILEAGE`, and `GRADE` labels in HTML with their corresponding values. Preserve the SVG's transparent margin by positioning overlays relative to the full 1320×640 canvas rather than cropping to the black border.

## HTML integration

```html
<link rel="icon" href="/assets/brand/favicon.ico" sizes="any">
<link rel="icon" href="/assets/brand/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/assets/brand/apple-touch-icon.png">
<link rel="manifest" href="/assets/brand/site.webmanifest">
<meta name="theme-color" content="#159447">
```
