# Brand assets

## Logo

The original **Digital Oil Sticker** logo (rounded sticker badge: orange oil drop in a teal circular gauge, "Digital Oil Sticker" wordmark in navy, teal check-terminated underline, folded sticker corner) was adopted by the product owner on 2026-07-31 as the product mark for the app interface and the static site.

- Canonical file: `assets/brand/logo-original.png` (**to be committed by the owner** — the source image was supplied outside the repository; commit the original before M02 consumes it).
- The bright green backdrop in the supplied capture is a chroma/screen background, **not** a brand color. Derivative exports must use a transparent background.
- Needed derivatives (produced under DOS-M02-002, the design-system issue): transparent-background SVG/PNG, monochrome/dark-mode variant, iOS and Android app-icon crops (drop-in-gauge mark without wordmark), splash/launch asset, and Netlify site header lockup.

## Approximate palette (from the logo; DOS-M02-002 freezes exact tokens)

| Role | Approx. value |
| --- | --- |
| Navy (wordmark, outline) | #1E2A4A |
| Teal (gauge ring, accents) | #2B7A8C |
| Orange (oil drop) | #E9A13B |
| White (badge field) | #FFFFFF |

## Usage rules

- The app interface (Phoenix LiveView `AppShell`) and the Netlify support site use this mark; no third-party or store badges may be altered to imitate it.
- Do not stretch, recolor the drop, or remove the check underline in primary lockups; small sizes may use the drop-in-gauge mark alone.
- Final accessibility-checked color tokens (contrast ratios against light/dark surfaces) are owned by DOS-M02-002 and must not be hardcoded ad hoc in feature work.
