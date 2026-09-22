// Mirrors the active skin's accent into the theme-color meta.
//
// The meta lives in the static root layout, outside LiveView's patch scope,
// so the server cannot re-render it when the skin changes — this hook is the
// bridge. The accent hex arrives as a data attribute rendered server-side
// from Skins.accent/1; the hook never computes colors and never stores
// anything (the localStorage allowlist stays exactly as it is).
//
// The scan page (/s) renders no layout and therefore no hook: browser chrome
// there keeps the brand-green default from the static markup.

const DEFAULT_THEME_COLOR = "#159447"

function metaEl() {
  return document.querySelector('meta[name="theme-color"]')
}

export const SkinChrome = {
  mounted() {
    this.apply()
  },

  updated() {
    this.apply()
  },

  destroyed() {
    const meta = metaEl()
    if (meta) meta.content = DEFAULT_THEME_COLOR
  },

  apply() {
    const meta = metaEl()
    if (!meta) return
    meta.content = this.el.dataset.themeColor || DEFAULT_THEME_COLOR
  },
}
