// The browser codec against the canonical vectors.
//
// The values never leave the device, so the server cannot generate the QR and
// the browser must encode. That means two implementations of one wire format,
// which is the classic setup for a silent divergence: the symptom is not a
// failing build, it is a sticker already in someone's windshield that stopped
// scanning. These vectors are the contract, emitted by the Elixir side with
// `mix dos.sticker_code.vectors`.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import * as code from '../../app/assets/js/sticker_code.js'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..', '..')

const FIXTURE = JSON.parse(
  readFileSync(join(REPO_ROOT, 'conformance', 'fixtures', 'sticker-code-vectors.json'), 'utf8')
)

const FIELDS = ['configuration_key', 'changed_on', 'odometer_m', 'grade', 'base_stock']

// Field-by-field rather than deep-equal on purpose: key order differs between
// the two languages and is not part of the contract, while a value difference
// entirely is.
function sameSticker(actual, expected) {
  return FIELDS.every(field => (actual[field] ?? null) === (expected[field] ?? null))
}

test('the vector file is substantial enough to hold a port honest', () => {
  assert.ok(FIXTURE.vectors.length > 10, 'too few vectors to catch a real divergence')
  assert.equal(FIXTURE.format_version, code.formatVersion)
})

test('the frozen tables have not diverged from the canonical side', () => {
  // An index into a reordered table is the silent failure this guards: every
  // code already printed would keep decoding, to the wrong oil.
  assert.deepEqual(code.grades(), FIXTURE.grades)
  assert.deepEqual(code.baseStocks(), FIXTURE.base_stocks)
})

test('every vector encodes to exactly its recorded code', () => {
  for (const vector of FIXTURE.vectors) {
    const result = code.encode(vector.sticker)

    assert.ok(result.ok, `${vector.name} failed to encode: ${result.error}`)
    assert.equal(
      result.code,
      vector.code,
      `${vector.name} encodes differently in the browser than in Elixir`
    )
  }
})

test('every vector decodes back to exactly its recorded values', () => {
  for (const vector of FIXTURE.vectors) {
    const result = code.decode(vector.code)

    assert.ok(result.ok, `${vector.name} failed to decode: ${result.error}`)
    assert.ok(
      sameSticker(result.sticker, vector.sticker),
      `${vector.name} decoded to ${JSON.stringify(result.sticker)}`
    )
  }
})

test('encoding is deterministic, which is what makes storage unnecessary', () => {
  for (const vector of FIXTURE.vectors) {
    assert.equal(code.encode(vector.sticker).code, code.encode(vector.sticker).code)
  }
})

test('case does not matter, because a code may be retyped from a screen', () => {
  // A shop reading a code off a POS display and typing it into another system
  // should not be defeated by case.
  for (const vector of FIXTURE.vectors) {
    const lowered = code.decode(vector.code.toLowerCase())

    assert.ok(lowered.ok, `${vector.name} would not decode in lower case`)
    assert.ok(sameSticker(lowered.sticker, vector.sticker))
  }
})

test('a fully populated code is 40 characters, so QR geometry is stable', () => {
  const typical = FIXTURE.vectors.find(v => v.name === 'typical')

  assert.equal(typical.code.length, 40)
})

test('codes use only the QR alphanumeric character set', () => {
  // Base32's alphabet is a subset of QR's alphanumeric mode, which encodes at
  // roughly half the bits per character of byte mode. That is the difference
  // between a code that stays readable on a small POS screen and one that does
  // not, so it is a property worth asserting rather than assuming.
  const QR_ALPHANUMERIC = /^[0-9A-Z $%*+\-./:]+$/

  for (const vector of FIXTURE.vectors) {
    assert.match(vector.code, QR_ALPHANUMERIC, `${vector.name} would force byte mode`)
  }
})

test('rubbish is refused rather than decoded into something plausible', () => {
  assert.equal(code.decode('this is not a sticker code').ok, false)
  assert.equal(code.decode(null).ok, false)
  assert.equal(code.decode('').ok, false)
  assert.equal(code.decode(FIXTURE.vectors[0].code.slice(0, 12)).ok, false)
})

test('a future format version is refused, not guessed at', () => {
  // Version byte 99 in a payload this version cannot interpret.
  const bytes = FIXTURE.vectors[0].code
  const mutated = 'B' + bytes.slice(1)

  const result = code.decode(mutated)

  assert.equal(result.ok, false)
  assert.equal(result.error, 'unsupported_format_version')
})
