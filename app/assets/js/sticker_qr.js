// Render a sticker code as an SVG QR symbol.
//
// SVG because the same symbol has to survive two very different fates. Printed
// on a die-cut sticker it gets scaled to whatever the die is, and a raster at
// the wrong DPI is how a code stops scanning. On a shop screen or a POS
// terminal it may be drawn at 120 CSS px on a low-DPI panel, where a resampled
// bitmap blurs module edges into each other. Vector geometry with integer
// coordinates avoids both.
//
// Everything here is client-side. The values never reach the server, so the
// server cannot render this — see DigitalOilSticker.StickerCode.

import qrcodegen from "../vendor/qrcodegen.js"

const {QrCode} = qrcodegen

// The spec's minimum, and not negotiable in practice. A symbol butted against
// UI chrome or a sticker's die-cut edge fails to scan on exactly the cheap
// imagers a POS lane uses.
const QUIET_ZONE_MODULES = 4

const ECC = {
  low: QrCode.Ecc.LOW,
  medium: QrCode.Ecc.MEDIUM,
  quartile: QrCode.Ecc.QUARTILE,
  high: QrCode.Ecc.HIGH,
}

/**
 * @param {string} text payload — a bare sticker code, or a URL carrying one
 * @param {object} [options]
 * @param {"low"|"medium"|"quartile"|"high"} [options.ecc]
 * @param {string} [options.title] accessible name; omit for a decorative symbol
 * @returns {{ok: true, svg: string, version: number, modules: number} | {ok: false, error: string}}
 */
export function toSvg(text, options = {}) {
  const {ecc = "quartile", title} = options

  if (typeof text !== "string" || text.length === 0) {
    return {ok: false, error: "empty_payload"}
  }

  const level = ECC[ecc]
  if (!level) return {ok: false, error: "unknown_ecc_level"}

  let symbol
  try {
    symbol = QrCode.encodeText(text, level)
  } catch {
    // Only realistic cause is a payload beyond the largest symbol, which for
    // this app would mean the code format grew without anyone noticing.
    return {ok: false, error: "payload_too_long"}
  }

  const span = symbol.size + QUIET_ZONE_MODULES * 2

  return {
    ok: true,
    svg: render(symbol, span, title),
    version: symbol.version,
    modules: symbol.size,
  }
}

function render(symbol, span, title) {
  const path = darkModulePath(symbol)
  const label = title
    ? `<title>${escapeText(title)}</title>`
    : ""
  const a11y = title ? `role="img"` : `role="presentation" aria-hidden="true"`

  // One path for every dark module rather than a rect each: a 29x29 symbol is
  // ~400 dark modules, and 400 elements is both a large string and slow to
  // paint on the underpowered browser in a payment terminal.
  //
  // viewBox is in MODULE units with no width/height, so the symbol scales to
  // whatever box it is given — a 25mm sticker or a 120px panel — without the
  // caller doing arithmetic.
  //
  // shape-rendering="crispEdges" turns off anti-aliasing. Anti-aliased module
  // edges are exactly what makes a small on-screen QR unreadable: the scanner
  // thresholds a grey boundary pixel one way or the other and the timing
  // pattern stops lining up.
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${span} ${span}" ${a11y} shape-rendering="crispEdges">`,
    label,
    // The quiet zone is drawn, not assumed. A transparent margin inherits
    // whatever is behind it, and "behind it" on a sticker is the artwork.
    `<rect width="${span}" height="${span}" fill="#FFFFFF"/>`,
    `<path d="${path}" fill="#000000"/>`,
    `</svg>`,
  ].join("")
}

// Horizontal runs merged into one rect each. Fewer, longer path commands than
// one per module, and it keeps the geometry on integer boundaries.
function darkModulePath(symbol) {
  const parts = []

  for (let y = 0; y < symbol.size; y++) {
    let runStart = -1

    for (let x = 0; x <= symbol.size; x++) {
      const dark = x < symbol.size && symbol.getModule(x, y)

      if (dark && runStart === -1) {
        runStart = x
      } else if (!dark && runStart !== -1) {
        const width = x - runStart
        parts.push(`M${runStart + QUIET_ZONE_MODULES} ${y + QUIET_ZONE_MODULES}h${width}v1h-${width}z`)
        runStart = -1
      }
    }
  }

  return parts.join("")
}

function escapeText(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

export const quietZoneModules = QUIET_ZONE_MODULES
