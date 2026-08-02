// The sticker code, in the browser.
//
// This is a port of DigitalOilSticker.StickerCode, and it exists because the
// values must never leave the device: the server cannot generate the QR, so
// the browser has to encode. Two implementations of one wire format is a real
// hazard — they drift, and the symptom is a sticker in someone's windshield
// that stopped scanning — so this one is held to the vectors the Elixir side
// emits (conformance/fixtures/sticker-code-vectors.json) rather than to a
// second reading of the spec.
//
// The format is documented once, in the Elixir module. Do not restate it here;
// read it there and keep this a transcription.

const FORMAT_VERSION = 1

// Days from 2000-01-01, so a two-byte field covers every plausible service
// date. Moving this reinterprets every code already printed.
const EPOCH_MS = Date.UTC(2000, 0, 1)
const MS_PER_DAY = 86_400_000

const ABSENT_DATE = 65_535
const MAX_DAYS = 65_534
const ABSENT_ODOMETER = 4_294_967_295
const ABSENT_BYTE = 255
const MANUAL_GRADE_BYTE = 254
const MAX_MANUAL_GRADE_BYTES = 20

// FROZEN, and frozen in the same order as the Elixir side. Append only; never
// reorder, never reuse a retired index. The vector test is what proves these
// two lists have not diverged.
const GRADES = [
  "0W-8", "0W-16", "0W-20", "0W-30", "0W-40",
  "5W-20", "5W-30", "5W-40", "5W-50",
  "10W-30", "10W-40", "10W-60", "15W-40", "20W-50",
]

const BASE_STOCKS = ["conventional", "synthetic_blend", "full_synthetic", "high_mileage"]

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

export const formatVersion = FORMAT_VERSION
export const grades = () => [...GRADES]
export const baseStocks = () => [...BASE_STOCKS]

/**
 * Fill in what a sparse sticker omits.
 *
 * `encode` accepts a map that simply leaves out what it does not have, while
 * `decode` always returns the complete shape — so round-trip identity holds
 * for a NORMALIZED sticker, not for any object that happens to encode.
 */
export function normalize(sticker = {}) {
  return {
    configuration_key: sticker.configuration_key ?? null,
    changed_on: sticker.changed_on ?? null,
    odometer_m: sticker.odometer_m ?? null,
    grade: sticker.grade ?? null,
    base_stock: sticker.base_stock ?? null,
  }
}

/** @returns {{ok: true, code: string} | {ok: false, error: string}} */
export function encode(input) {
  const sticker = normalize(input)

  const uuid = uuidToBytes(sticker.configuration_key)
  if (!uuid) return fail("invalid_configuration_key")

  const days = encodeDate(sticker.changed_on)
  if (days === null) return fail("date_out_of_range")

  const metres = encodeOdometer(sticker.odometer_m)
  if (metres === null) return fail("odometer_out_of_range")

  const grade = encodeGrade(sticker.grade)
  if (!grade) return fail("manual_grade_too_long")

  const stock = encodeStock(sticker.base_stock)
  if (stock === null) return fail("unknown_base_stock")

  const head = new Uint8Array(25)
  head[0] = FORMAT_VERSION
  head.set(uuid, 1)
  writeUint16(head, 17, days)
  writeUint32(head, 19, metres)
  head[23] = grade.byte
  head[24] = stock

  const bytes = grade.tail.length ? concat(head, grade.tail) : head
  return {ok: true, code: base32Encode(bytes)}
}

/** @returns {{ok: true, sticker: object} | {ok: false, error: string}} */
export function decode(code) {
  if (typeof code !== "string") return fail("not_a_string")

  const bytes = base32Decode(code)
  if (!bytes) return fail("not_base32")
  if (bytes.length < 25) return fail("malformed")
  if (bytes[0] !== FORMAT_VERSION) return fail("unsupported_format_version")

  const key = bytesToUuid(bytes.subarray(1, 17))
  const days = readUint16(bytes, 17)
  const metres = readUint32(bytes, 19)
  const gradeByte = bytes[23]
  const stockByte = bytes[24]
  const tail = bytes.subarray(25)

  const grade = decodeGrade(gradeByte, tail)
  if (grade === undefined) return fail("unknown_grade_index")
  if (grade === null && gradeByte === MANUAL_GRADE_BYTE) return fail("malformed_manual_grade")

  const stock = decodeStock(stockByte)
  if (stock === undefined) return fail("unknown_base_stock_index")

  // A tail on a non-manual grade means the code is longer than its contents
  // explain, which is corruption rather than a format we do not know.
  if (gradeByte !== MANUAL_GRADE_BYTE && tail.length > 0) return fail("unexpected_tail")

  return {
    ok: true,
    sticker: {
      configuration_key: key,
      changed_on: days === ABSENT_DATE ? null : dateFromDays(days),
      odometer_m: metres === ABSENT_ODOMETER ? null : metres,
      grade,
      base_stock: stock,
    },
  }
}

// -- field codecs -------------------------------------------------------------

function encodeDate(value) {
  if (value === null) return ABSENT_DATE

  const days = daysFromDate(value)
  if (days === null || days < 0 || days > MAX_DAYS) return null
  return days
}

function encodeOdometer(value) {
  if (value === null) return ABSENT_ODOMETER
  if (!Number.isInteger(value) || value < 0 || value >= ABSENT_ODOMETER) return null
  return value
}

function encodeGrade(value) {
  if (value === null) return {byte: ABSENT_BYTE, tail: new Uint8Array(0)}

  const index = GRADES.indexOf(value)
  if (index !== -1) return {byte: index, tail: new Uint8Array(0)}

  // A grade the user typed themselves, carried verbatim so scanning still
  // autofills what they actually put in.
  const encoded = new TextEncoder().encode(value)
  if (encoded.length === 0 || encoded.length > MAX_MANUAL_GRADE_BYTES) return null

  const tail = new Uint8Array(encoded.length + 1)
  tail[0] = encoded.length
  tail.set(encoded, 1)
  return {byte: MANUAL_GRADE_BYTE, tail}
}

function encodeStock(value) {
  if (value === null) return ABSENT_BYTE

  const index = BASE_STOCKS.indexOf(value)
  return index === -1 ? null : index
}

// `undefined` means refuse; `null` means genuinely absent.
function decodeGrade(byte, tail) {
  if (byte === ABSENT_BYTE) return null

  if (byte === MANUAL_GRADE_BYTE) {
    if (tail.length < 1) return null
    const length = tail[0]
    if (length === 0 || length > MAX_MANUAL_GRADE_BYTES || tail.length !== length + 1) return null
    return new TextDecoder("utf-8", {fatal: false}).decode(tail.subarray(1, length + 1))
  }

  // A retired or not-yet-known index. Refused rather than approximated: naming
  // the wrong oil is worse than admitting the code is unreadable.
  return byte < GRADES.length ? GRADES[byte] : undefined
}

function decodeStock(byte) {
  if (byte === ABSENT_BYTE) return null
  return byte < BASE_STOCKS.length ? BASE_STOCKS[byte] : undefined
}

// -- dates --------------------------------------------------------------------
//
// Handled as UTC throughout. A service date is a calendar date, not an instant,
// and running it through a local-time constructor would shift it by a day for
// anyone west of UTC.

function daysFromDate(value) {
  const iso = typeof value === "string" ? value : isoFromDate(value)
  if (!iso) return null

  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  if (!match) return null

  const ms = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  if (Number.isNaN(ms)) return null

  return Math.round((ms - EPOCH_MS) / MS_PER_DAY)
}

function isoFromDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10)
  }
  return null
}

function dateFromDays(days) {
  return new Date(EPOCH_MS + days * MS_PER_DAY).toISOString().slice(0, 10)
}

// -- primitives ---------------------------------------------------------------

function uuidToBytes(value) {
  if (typeof value !== "string") return null

  const hex = value.replace(/-/g, "")
  if (!/^[0-9a-fA-F]{32}$/.test(hex)) return null

  const bytes = new Uint8Array(16)
  for (let i = 0; i < 16; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16)
  return bytes
}

function bytesToUuid(bytes) {
  const hex = Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("")
  return [
    hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20),
  ].join("-")
}

function writeUint16(target, offset, value) {
  target[offset] = (value >>> 8) & 255
  target[offset + 1] = value & 255
}

function writeUint32(target, offset, value) {
  // `>>> 0` keeps the arithmetic unsigned: the top odometer values exceed the
  // range of JavaScript's signed 32-bit bitwise operators.
  target[offset] = (value >>> 24) & 255
  target[offset + 1] = (value >>> 16) & 255
  target[offset + 2] = (value >>> 8) & 255
  target[offset + 3] = value & 255
}

const readUint16 = (bytes, offset) => (bytes[offset] << 8) | bytes[offset + 1]

const readUint32 = (bytes, offset) =>
  bytes[offset] * 16_777_216 + (bytes[offset + 1] << 16) + (bytes[offset + 2] << 8) + bytes[offset + 3]

function concat(a, b) {
  const out = new Uint8Array(a.length + b.length)
  out.set(a, 0)
  out.set(b, a.length)
  return out
}

// RFC 4648 base32, unpadded — matching Elixir's Base.encode32(padding: false).
function base32Encode(bytes) {
  let out = ""
  let bits = 0
  let value = 0

  for (const byte of bytes) {
    value = (value << 8) | byte
    bits += 8
    while (bits >= 5) {
      out += BASE32[(value >>> (bits - 5)) & 31]
      bits -= 5
    }
  }

  if (bits > 0) out += BASE32[(value << (5 - bits)) & 31]
  return out
}

function base32Decode(text) {
  let bits = 0
  let value = 0
  const out = []

  // Uppercased first: a code read off a windshield or retyped should not fail
  // on case alone.
  for (const char of text.toUpperCase()) {
    const index = BASE32.indexOf(char)
    if (index === -1) return null

    value = (value << 5) | index
    bits += 5
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255)
      bits -= 8
    }
  }

  return new Uint8Array(out)
}

const fail = error => ({ok: false, error})
