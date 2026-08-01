import { spawnSync } from 'node:child_process'
import { sleep } from './util.mjs'

export const API_VERSION = '2022-11-28'
const WRITE_SPACING_MS = 1100
const MAX_RETRIES = 5
let lastWriteAt = 0

const ENV = {
  ...process.env,
  GH_PROMPT_DISABLED: '1',
  GH_NO_UPDATE_NOTIFIER: '1',
  GH_PAGER: 'cat',
  NO_COLOR: '1',
  CLICOLOR: '0',
}

// Run gh with an argument array (never a shell string). `write: true` enforces
// serialized spacing between content-creating requests and retry-with-backoff
// on rate/secondary-limit responses. Tokens never pass through this module.
export function gh(args, { write = false, allowFail = false, input = null } = {}) {
  for (let attempt = 0; ; attempt++) {
    if (write) {
      const wait = WRITE_SPACING_MS - (Date.now() - lastWriteAt)
      if (wait > 0) sleep(wait)
    }
    const res = spawnSync('gh', args, {
      encoding: 'utf8',
      shell: false,
      windowsHide: true,
      input: input === null ? undefined : input,
      env: ENV,
      maxBuffer: 128 * 1024 * 1024,
    })
    if (write) lastWriteAt = Date.now()
    if (res.error) throw res.error
    if (res.status === 0) return res.stdout
    const err = `${res.stderr ?? ''}\n${res.stdout ?? ''}`
    const retriable = /rate limit|secondary|abuse|submitted too quickly|HTTP 5\d\d|502|503|timed? ?out|Something went wrong/i.test(err)
    if (retriable && attempt < MAX_RETRIES) {
      const ra = err.match(/retry[- ]after[:\s]+(\d+)/i)
      const delay = ra ? (Number(ra[1]) + 2) * 1000 : Math.min(30_000 * 2 ** attempt, 300_000)
      console.error(`  transient gh failure (attempt ${attempt + 1}/${MAX_RETRIES}); sleeping ${Math.round(delay / 1000)}s`)
      sleep(delay)
      continue
    }
    if (allowFail) return null
    throw new Error(`gh ${args.join(' ')} failed (exit ${res.status}):\n${err.slice(0, 4000)}`)
  }
}

export function apiJson(path, { method = 'GET', body = null, allowFail = false } = {}) {
  const args = ['api', '-H', `X-GitHub-Api-Version: ${API_VERSION}`]
  if (method !== 'GET') args.push('-X', method)
  if (body !== null) args.push('--input', '-')
  args.push(path)
  const out = gh(args, {
    write: method !== 'GET',
    allowFail,
    input: body === null ? null : JSON.stringify(body),
  })
  if (out === null) return null
  return out.trim() === '' ? {} : JSON.parse(out)
}

// Paginated REST list: maps each element through a jq expression, one JSON per line.
export function apiList(path, jqMap = '.') {
  const args = [
    'api', '-H', `X-GitHub-Api-Version: ${API_VERSION}`,
    '--paginate', path, '--jq', `.[] | ${jqMap}`,
  ]
  const out = gh(args)
  return out.split('\n').filter(l => l.trim() !== '').map(l => JSON.parse(l))
}

// GraphQL with alias-level error checking. `variables` values are passed with
// -F (typed) for numbers/booleans and -f for strings.
export function graphql(query, variables = {}, { write = false } = {}) {
  const args = ['api', 'graphql', '-f', `query=${query}`]
  for (const [k, v] of Object.entries(variables)) {
    if (typeof v === 'number' || typeof v === 'boolean') args.push('-F', `${k}=${v}`)
    else args.push('-f', `${k}=${v}`)
  }
  const out = gh(args, { write })
  const parsed = JSON.parse(out)
  if (parsed.errors?.length) {
    throw new Error(`GraphQL errors: ${JSON.stringify(parsed.errors).slice(0, 4000)}`)
  }
  const data = parsed.data ?? {}
  for (const [alias, value] of Object.entries(data)) {
    if (value === null) throw new Error(`GraphQL alias "${alias}" returned null (silent failure)`)
  }
  return data
}
