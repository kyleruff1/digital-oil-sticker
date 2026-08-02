// The SVG QR renderer.
//
// The encoding itself is a vendored reference implementation and is not what
// this file is testing. What is tested is the part written here: the geometry.
// A renderer can produce a perfectly valid module matrix and still emit a
// symbol nothing will scan — transposed axes, an off-by-one quiet zone,
// inverted fills, run-merging that drops the last module of a row. Those are
// invisible on a screen at a glance and fatal on a windshield.
//
// So the SVG is parsed BACK into a module grid and compared to the matrix the
// encoder produced. If the path does not say what the encoder meant, that is a
// failure here rather than a sticker that scans on one reader and not another.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import qrcodegen from '../../app/assets/vendor/qrcodegen.js'
import { toSvg, quietZoneModules } from '../../app/assets/js/sticker_qr.js'
import * as code from '../../app/assets/js/sticker_code.js'

const { QrCode } = qrcodegen

// A real code rather than a made-up string: this is the payload shape the
// renderer will actually be handed.
const SAMPLE = code.encode({
  configuration_key: '000384cf-aee6-5ba8-968a-1fe30158f387',
  changed_on: '2026-03-15',
  odometer_m: 77_570_381,
  grade: '0W-20',
  base_stock: 'full_synthetic',
})

test('the sample payload is a real sticker code', () => {
  assert.ok(SAMPLE.ok)
  assert.equal(SAMPLE.code.length, 40)
})

// Reads the emitted path back into a boolean grid. Deliberately a separate,
// dumber implementation than the renderer's run-merging — reusing the
// renderer's own logic to check the renderer would prove nothing.
function gridFromSvg(svg, span) {
  const grid = Array.from({ length: span }, () => new Array(span).fill(false))

  const d = /<path d="([^"]*)"/.exec(svg)
  assert.ok(d, 'no module path in the SVG')

  const runs = d[1].matchAll(/M(\d+) (\d+)h(\d+)v1h-\d+z/g)
  let seen = 0

  for (const [, x, y, width] of runs) {
    seen++
    for (let i = 0; i < Number(width); i++) {
      const col = Number(x) + i
      const row = Number(y)
      assert.ok(col < span && row < span, `run escapes the viewBox at ${col},${row}`)
      assert.equal(grid[row][col], false, `overlapping runs at ${col},${row}`)
      grid[row][col] = true
    }
  }

  assert.ok(seen > 0, 'the path parsed to zero runs, so the regex and the renderer disagree')
  return grid
}

test('the rendered path is the encoder matrix, module for module', () => {
  const symbol = QrCode.encodeText(SAMPLE.code, QrCode.Ecc.QUARTILE)
  const result = toSvg(SAMPLE.code, { ecc: 'quartile' })

  assert.ok(result.ok)
  assert.equal(result.modules, symbol.size)

  const span = symbol.size + quietZoneModules * 2
  const grid = gridFromSvg(result.svg, span)

  for (let y = 0; y < symbol.size; y++) {
    for (let x = 0; x < symbol.size; x++) {
      assert.equal(
        grid[y + quietZoneModules][x + quietZoneModules],
        symbol.getModule(x, y),
        // Named because a transposition passes every other assertion in this
        // file: same module count, same density, same bounding box.
        `module ${x},${y} disagrees with the encoder (a transposed or shifted grid looks fine until it is scanned)`
      )
    }
  }
})

test('the quiet zone is four modules on every side and genuinely empty', () => {
  const result = toSvg(SAMPLE.code)
  const span = result.modules + quietZoneModules * 2
  const grid = gridFromSvg(result.svg, span)

  assert.equal(quietZoneModules, 4, 'four is the spec minimum, not a tunable')

  for (let y = 0; y < span; y++) {
    for (let x = 0; x < span; x++) {
      const inside =
        x >= quietZoneModules &&
        y >= quietZoneModules &&
        x < span - quietZoneModules &&
        y < span - quietZoneModules

      if (!inside) {
        assert.equal(grid[y][x], false, `a dark module sits in the quiet zone at ${x},${y}`)
      }
    }
  }
})

test('the quiet zone is painted white rather than left transparent', () => {
  // Transparent means it inherits the sticker artwork behind it, which is not a
  // quiet zone at all.
  const result = toSvg(SAMPLE.code)
  const span = result.modules + quietZoneModules * 2

  assert.match(
    result.svg,
    new RegExp(`<rect width="${span}" height="${span}" fill="#FFFFFF"/>`)
  )
})

test('the viewBox is in module units so the symbol scales to any physical size', () => {
  const result = toSvg(SAMPLE.code)
  const span = result.modules + quietZoneModules * 2

  assert.match(result.svg, new RegExp(`viewBox="0 0 ${span} ${span}"`))

  // No width/height: a fixed pixel size would be wrong for a 25 mm die-cut
  // sticker and wrong again for a 120 px POS panel.
  assert.doesNotMatch(result.svg, /<svg[^>]*\swidth=/)
  assert.doesNotMatch(result.svg, /<svg[^>]*\sheight=/)
})

test('anti-aliasing is turned off', () => {
  // Grey module edges are a leading cause of a small on-screen code failing to
  // scan: the imager thresholds the boundary pixel one way or the other and the
  // timing pattern stops lining up.
  assert.match(toSvg(SAMPLE.code).svg, /shape-rendering="crispEdges"/)
})

test('module coordinates are integers', () => {
  // A fractional coordinate is what produces a half-lit module edge on a
  // low-DPI panel, whatever shape-rendering says.
  const d = /<path d="([^"]*)"/.exec(toSvg(SAMPLE.code).svg)[1]

  assert.doesNotMatch(d, /\d\.\d/, 'a fractional coordinate reached the path')
})

test('the code area is pure black on pure white', () => {
  // Not brand green. A tinted symbol reduces contrast for a laser scanner that
  // reads a single wavelength, and the brand is expressed around the code.
  const svg = toSvg(SAMPLE.code).svg
  const fills = [...svg.matchAll(/fill="([^"]*)"/g)].map(m => m[1])

  assert.deepEqual([...new Set(fills)].sort(), ['#000000', '#FFFFFF'])
})

test('every error-correction level renders, and higher levels cost modules', () => {
  const sizes = ['low', 'medium', 'quartile', 'high'].map(ecc => {
    const result = toSvg(SAMPLE.code, { ecc })
    assert.ok(result.ok, `${ecc} did not render`)
    return result.modules
  })

  // Monotonic non-decreasing: more recovery capacity never buys a smaller
  // symbol. A drop would mean the level argument is being ignored.
  for (let i = 1; i < sizes.length; i++) {
    assert.ok(sizes[i] >= sizes[i - 1], 'a higher EC level produced a smaller symbol')
  }
})

test('a 40-character code stays at the size the sticker design was drawn for', () => {
  // The sticker layout reserves a fixed box. If a routine payload silently
  // stepped up a QR version, every module would shrink inside that same box.
  const result = toSvg(SAMPLE.code, { ecc: 'quartile' })

  assert.equal(result.version, 3)
  assert.equal(result.modules, 29)
})

test('a manual grade lengthens the payload without breaking the render', () => {
  // The manual-grade tail is the one thing that varies the payload length, so
  // it is the one thing that can move the QR version under a real user.
  const longer = code.encode({
    configuration_key: '000384cf-aee6-5ba8-968a-1fe30158f387',
    changed_on: '2026-03-15',
    odometer_m: 77_570_381,
    grade: 'x'.repeat(20),
    base_stock: 'full_synthetic',
  })

  const result = toSvg(longer.code, { ecc: 'quartile' })

  assert.ok(result.ok)
  assert.ok(result.modules >= 29, 'a longer payload somehow shrank the symbol')
})

test('the accessible name is opt-in and escaped', () => {
  const bare = toSvg(SAMPLE.code)
  assert.match(bare.svg, /role="presentation"/)
  assert.match(bare.svg, /aria-hidden="true"/)
  assert.doesNotMatch(bare.svg, /<title>/)

  const named = toSvg(SAMPLE.code, { title: 'Oil change record <&>' })
  assert.match(named.svg, /role="img"/)
  assert.match(named.svg, /<title>Oil change record &lt;&amp;&gt;<\/title>/)
  assert.doesNotMatch(named.svg, /aria-hidden/)
})

test('the payload never appears in the SVG as text', () => {
  // The code carries the user's values. It belongs in the modules, not in a
  // title, a comment, or a data attribute where it would be copied out with the
  // markup.
  const named = toSvg(SAMPLE.code, { title: 'Oil change record' })

  assert.doesNotMatch(named.svg, new RegExp(SAMPLE.code))
})

test('bad input is refused rather than rendered as an empty symbol', () => {
  assert.deepEqual(toSvg(''), { ok: false, error: 'empty_payload' })
  assert.deepEqual(toSvg(null), { ok: false, error: 'empty_payload' })
  assert.deepEqual(toSvg(SAMPLE.code, { ecc: 'perfect' }), { ok: false, error: 'unknown_ecc_level' })
})

test('a payload too large for any symbol is refused, not truncated', () => {
  const result = toSvg('A'.repeat(10_000))

  assert.equal(result.ok, false)
  assert.equal(result.error, 'payload_too_long')
})

test('rendering is deterministic', () => {
  // Same reason the code itself is: nothing is stored, so the symbol has to be
  // reproducible from the values alone.
  assert.equal(toSvg(SAMPLE.code).svg, toSvg(SAMPLE.code).svg)
})

test('the vendored library still carries its license header', () => {
  // Stripping it while reformatting or minifying would ship an MIT violation
  // in a production asset.
  const source = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'app', 'assets', 'vendor', 'qrcodegen.js'),
    'utf8'
  )

  assert.match(source, /Copyright \(c\) Project Nayuki\. \(MIT License\)/)
  assert.match(source, /Permission is hereby granted, free of charge/)
})
