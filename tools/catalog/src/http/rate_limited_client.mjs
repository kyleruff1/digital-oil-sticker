// Courteous HTTP client (DOS-M03-004): ONE global limiter across all sources,
// concurrency 1, >= SPACING_MS between request starts, Retry-After honored,
// exponential backoff with full jitter, bounded attempts. Typed errors only.
// Every response is cached verbatim with a provenance envelope; warm reruns
// make zero network requests (resume/idempotency).

import { createHash } from 'node:crypto'
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

const SPACING_MS = 1100
const MAX_ATTEMPTS = 5
const RETRIABLE_STATUS = new Set([408, 429, 500, 502, 503, 504])
const USER_AGENT = 'digital-oil-sticker-catalog-build (courteous serialized fetch; contact: repo owner)'

let lastStartAt = 0
const sleep = ms => new Promise(r => setTimeout(r, ms))

export class TypedError extends Error {
  constructor(kind, message, extra = {}) {
    super(`${kind}: ${message}`)
    this.kind = kind // rate_limited | transport | upstream_status | schema | exhausted
    Object.assign(this, extra)
  }
}

export function makeClient({ rawDir, counters = {} }) {
  counters.requests ??= 0
  counters.cache_hits ??= 0
  counters.retries ??= 0

  async function fetchCached(name, url, { accept = 'application/json' } = {}) {
    const bodyPath = join(rawDir, `${name}.body`)
    const metaPath = join(rawDir, `${name}.meta.json`)
    if (existsSync(bodyPath) && existsSync(metaPath)) {
      const meta = JSON.parse(readFileSync(metaPath, 'utf8'))
      const body = readFileSync(bodyPath)
      const sha = createHash('sha256').update(body).digest('hex')
      if (sha !== meta.sha256) throw new TypedError('schema', `${name}: cached body hash mismatch — cache corrupted, delete and refetch`)
      counters.cache_hits++
      return { body: body.toString('utf8'), meta, fromCache: true }
    }

    let attempt = 0
    for (;;) {
      const wait = SPACING_MS - (Date.now() - lastStartAt)
      if (wait > 0) await sleep(wait)
      lastStartAt = Date.now()
      counters.requests++
      let res
      try {
        res = await fetch(url, { headers: { 'User-Agent': USER_AGENT, Accept: accept } })
      } catch (e) {
        if (++attempt >= MAX_ATTEMPTS) throw new TypedError('exhausted', `${name}: transport failure after ${attempt} attempts: ${e.message}`)
        counters.retries++
        await sleep(backoff(attempt))
        continue
      }
      if (RETRIABLE_STATUS.has(res.status)) {
        if (++attempt >= MAX_ATTEMPTS) throw new TypedError('exhausted', `${name}: HTTP ${res.status} after ${attempt} attempts`)
        counters.retries++
        const ra = Number(res.headers.get('retry-after'))
        await sleep(Number.isFinite(ra) && ra > 0 ? (ra + 1) * 1000 : backoff(attempt))
        continue
      }
      if (!res.ok) throw new TypedError('upstream_status', `${name}: HTTP ${res.status} from ${url}`, { status: res.status })

      const buf = Buffer.from(await res.arrayBuffer())
      const sha256 = createHash('sha256').update(buf).digest('hex')
      const meta = {
        name, url, status: res.status,
        retrieved_at: new Date().toISOString(),
        sha256,
        content_type: res.headers.get('content-type'),
        content_length: buf.length,
      }
      mkdirSync(dirname(bodyPath), { recursive: true })
      writeFileSync(bodyPath, buf)
      writeFileSync(metaPath, JSON.stringify(meta, null, 2) + '\n')
      return { body: buf.toString('utf8'), meta, fromCache: false }
    }
  }

  return { fetchCached, counters }
}

function backoff(attempt) {
  const cap = Math.min(30_000 * 2 ** (attempt - 1), 300_000)
  return Math.floor(Math.random() * cap) // full jitter
}
