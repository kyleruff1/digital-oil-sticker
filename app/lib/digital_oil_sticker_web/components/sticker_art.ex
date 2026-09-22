defmodule DigitalOilStickerWeb.Components.StickerArt do
  @moduledoc """
  The sticker artwork, inline — `priv/static/images/dos-logo.svg` transcribed
  element-for-element into HEEx so its paints can resolve through CSS custom
  properties (the skin system). A static `<img>` cannot be themed: its fills
  are frozen at export, which is why this module exists.

  ## The transcription contract

  `sticker_art_parity_test.exs` holds this markup equal to the SVG file,
  element by element, attribute by attribute. The permitted deltas — the ONLY
  differences from the file — are:

    * the root `<svg>` drops `role`/`aria-labelledby` and the `<title>`/
      `<desc>` pair, and gains `aria-hidden="true"` plus the positioning
      classes the `<img>` used to carry. The artwork is decorative by
      contract: the HTML viewport overlays carry every piece of information.
    * ids are namespaced (`duotone` → `dos-art-duotone`, `flag-checkers` →
      `dos-art-checkers`) as defense against future page-level collisions.
      At most one sticker renders per document (StickerLive and ScanLive are
      different routes), so fixed ids are safe.
    * themable elements gain a `dos-art-*` class. `app.css` maps each class
      to `var(--skin-…)` paints. Presentation attributes are KEPT verbatim —
      stylesheet rules beat presentation attributes in the SVG cascade, so
      the vars win when the stylesheet loads and the attributes are the
      no-CSS fallback (and the parity test's comparison anchor).

  No `style=` anywhere: CSP is `style-src 'self'`, and SVG presentation
  attributes cannot consume `var()` — the classes are the entire theming
  surface.
  """
  use Phoenix.Component

  @doc "The sticker artwork as inline SVG. Decorative; no attrs."
  def artwork(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1320 640"
      aria-hidden="true"
      class="absolute inset-0 h-full w-full select-none"
    >
      <defs>
        <linearGradient id="dos-art-duotone" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#159447" class="dos-art-stop-a" /><stop
            offset=".38"
            stop-color="#159447"
            class="dos-art-stop-a"
          />
          <stop offset=".49" stop-color="#F7FAF8" class="dos-art-stop-mid" /><stop
            offset=".51"
            stop-color="#F7FAF8"
            class="dos-art-stop-mid"
          />
          <stop offset=".62" stop-color="#1769AA" class="dos-art-stop-b" /><stop
            offset="1"
            stop-color="#1769AA"
            class="dos-art-stop-b"
          />
        </linearGradient>
        <pattern id="dos-art-checkers" width="28" height="28" patternUnits="userSpaceOnUse">
          <rect width="28" height="28" fill="#FFFFFF" class="dos-art-checker-light" />
          <rect width="14" height="14" fill="#101820" class="dos-art-checker-dark" />
          <rect x="14" y="14" width="14" height="14" fill="#101820" class="dos-art-checker-dark" />
        </pattern>
      </defs>

      <g transform="translate(60 60)">
        <rect
          x="36"
          y="36"
          width="1128"
          height="448"
          rx="62"
          fill="#FFFFFF"
          fill-opacity=".72"
          stroke="#F7FAF8"
          stroke-opacity=".94"
          stroke-width="30"
          class="dos-art-body"
        />
        <rect
          x="36"
          y="36"
          width="1128"
          height="448"
          rx="62"
          fill="none"
          stroke="#101820"
          stroke-width="16"
          class="dos-art-border"
        />
        <rect
          x="47"
          y="47"
          width="1106"
          height="426"
          rx="51"
          fill="none"
          stroke="url(#dos-art-duotone)"
          stroke-width="5"
        />

        <g transform="translate(82 76)">
          <rect
            width="48"
            height="48"
            rx="7"
            fill="#159447"
            stroke="#F7FAF8"
            stroke-width="3"
            class="dos-art-brand-a"
          />
          <rect
            x="59"
            width="48"
            height="48"
            rx="7"
            fill="#1769AA"
            stroke="#F7FAF8"
            stroke-width="3"
            class="dos-art-brand-b"
          />
          <rect
            y="59"
            width="48"
            height="48"
            rx="7"
            fill="#101820"
            stroke="#F7FAF8"
            stroke-width="3"
            class="dos-art-ink"
          />
          <rect
            x="59"
            y="59"
            width="48"
            height="48"
            rx="7"
            fill="url(#dos-art-duotone)"
            stroke="#F7FAF8"
            stroke-width="3"
            class="dos-art-duo-stroke"
          />
        </g>

        <g font-family="Arial Black, Arial, Helvetica, sans-serif">
          <text
            x="228"
            y="116"
            fill="#1769AA"
            stroke="#F7FAF8"
            stroke-width="3"
            paint-order="stroke fill"
            font-size="50"
            font-weight="800"
            letter-spacing="3"
            class="dos-art-brand-b"
          >
            DIGITAL
          </text>
          <text
            x="222"
            y="184"
            fill="#101820"
            stroke="#F7FAF8"
            stroke-width="5"
            paint-order="stroke fill"
            font-size="80"
            font-weight="900"
            letter-spacing="-3"
            class="dos-art-ink"
          >
            OIL STICKER
          </text>
        </g>
        <path d="M82 211h1031" stroke="#159447" stroke-width="11" class="dos-art-rule-a" />
        <path d="M82 222h1031" stroke="#1769AA" stroke-width="4" class="dos-art-rule-b" />

        <g
          font-family="Arial, Helvetica, sans-serif"
          fill="#101820"
          stroke="#F7FAF8"
          stroke-width="4"
          paint-order="stroke fill"
          text-anchor="middle"
          class="dos-art-ink"
        >
          <text x="600" y="274" font-size="46" font-weight="900" letter-spacing="2">
            NEXT SERVICE DUE
          </text>
        </g>

        <g transform="translate(972 62) scale(.92)">
          <path
            d="M23 24 96 139M147 24 67 139"
            fill="none"
            stroke="#F7FAF8"
            stroke-width="17"
            stroke-linecap="round"
            class="dos-art-halo"
          />
          <path
            d="M23 24 96 139M147 24 67 139"
            fill="none"
            stroke="#101820"
            stroke-width="9"
            stroke-linecap="round"
            class="dos-art-inkline"
          />
          <g transform="rotate(-12 22 20)">
            <path
              d="M20 18C48-12 68 43 112 5c-12 32 5 57-13 84C67 118 46 59 10 101c10-32-3-62 10-83Z"
              fill="url(#dos-art-checkers)"
              stroke="#F7FAF8"
              stroke-width="13"
              stroke-linejoin="round"
              class="dos-art-halo"
            />
            <path
              d="M20 18C48-12 68 43 112 5c-12 32 5 57-13 84C67 118 46 59 10 101c10-32-3-62 10-83Z"
              fill="url(#dos-art-checkers)"
              stroke="#101820"
              stroke-width="6"
              stroke-linejoin="round"
              class="dos-art-inkline"
            />
            <path
              d="M15 52c31-24 55 27 91 2"
              fill="none"
              stroke="#1769AA"
              stroke-width="3"
              opacity=".6"
              class="dos-art-rule-b"
            />
          </g>
          <g transform="translate(170 0) scale(-1 1) rotate(-12 22 20)">
            <path
              d="M20 18C48-12 68 43 112 5c-12 32 5 57-13 84C67 118 46 59 10 101c10-32-3-62 10-83Z"
              fill="url(#dos-art-checkers)"
              stroke="#F7FAF8"
              stroke-width="13"
              stroke-linejoin="round"
              class="dos-art-halo"
            />
            <path
              d="M20 18C48-12 68 43 112 5c-12 32 5 57-13 84C67 118 46 59 10 101c10-32-3-62 10-83Z"
              fill="url(#dos-art-checkers)"
              stroke="#101820"
              stroke-width="6"
              stroke-linejoin="round"
              class="dos-art-inkline"
            />
            <path
              d="M15 52c31-24 55 27 91 2"
              fill="none"
              stroke="#159447"
              stroke-width="3"
              opacity=".6"
              class="dos-art-rule-a"
            />
          </g>
        </g>

        <path
          d="M1068 477c44-13 76-43 91-88v29c0 36-29 65-65 65h-26Z"
          fill="#1769AA"
          class="dos-art-fill-b"
        />
        <path
          d="M1085 478c32-18 55-44 68-77-14 40-37 66-70 81Z"
          fill="#159447"
          class="dos-art-fill-a"
        />
        <path
          d="M1068 477c31-22 53-52 63-89-22 30-49 49-81 59l18 30Z"
          fill="#FFFFFF"
          fill-opacity=".82"
          stroke="#F7FAF8"
          stroke-width="15"
          stroke-linejoin="round"
          class="dos-art-peel-face dos-art-halo"
        />
        <path
          d="M1068 477c31-22 53-52 63-89-22 30-49 49-81 59l18 30Z"
          fill="#FFFFFF"
          fill-opacity=".82"
          stroke="#101820"
          stroke-width="7"
          stroke-linejoin="round"
          class="dos-art-peel-face dos-art-inkline"
        />
      </g>
    </svg>
    """
  end
end
