import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

export function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
}

// Read a text file, reject BOM, normalize CRLF to LF.
export function readTextLF(path) {
  const buf = readFileSync(path)
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
    throw new Error(`${path}: UTF-8 BOM present; files must be BOM-free`)
  }
  const text = buf.toString('utf8')
  if (text.includes('�')) throw new Error(`${path}: invalid UTF-8 (replacement character found)`)
  return text.replace(/\r\n/g, '\n')
}

export function sha256(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex')
}

export function writeFileAtomic(path, content) {
  mkdirSync(dirname(path), { recursive: true })
  const tmp = path + '.tmp'
  writeFileSync(tmp, content, { encoding: 'utf8' })
  renameSync(tmp, path)
}

export function readJsonIf(path, fallback) {
  if (!existsSync(path)) return fallback
  return JSON.parse(readTextLF(path))
}

export function fail(msg) {
  console.error(`ERROR: ${msg}`)
  process.exit(1)
}

// Topological sort over ids given blockedBy edges; throws listing a cycle if one exists.
export function assertAcyclic(issues) {
  const state = new Map()
  const byId = new Map(issues.map(i => [i.id, i]))
  const stack = []
  function visit(id) {
    const s = state.get(id)
    if (s === 2) return
    if (s === 1) throw new Error(`dependency cycle: ${[...stack, id].join(' -> ')}`)
    state.set(id, 1)
    stack.push(id)
    for (const dep of byId.get(id)?.blockedBy ?? []) visit(dep)
    stack.pop()
    state.set(id, 2)
  }
  for (const i of issues) visit(i.id)
}
