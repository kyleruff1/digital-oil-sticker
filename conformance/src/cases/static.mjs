// Netlify static-origin conformance (FR-18, AC-16). Distinct from the app
// origin the other cases exercise: the Fly LiveView app runs at
// digitaloilsticker.com and holds the interactive session; the static site at
// digitaloilsticker.net serves marketing, help, privacy, and attribution — HTML
// and CSS only, no runtime, no scripts to a third party, no cookie, no claim
// that a user has an account. INV-27 is what tells the two boundaries apart,
// and these cases assert the static one so the boundary is testable rather
// than described.
//
// The static origin address is read from STATIC_ORIGIN so preview deploys can
// be checked before the production DNS lands. When STATIC_ORIGIN is unset or
// unreachable — the state today, because DOS-M09-007 owns the DNS cutover to
// Netlify — each case returns UNPROVEN with a reason that names the owner
// action, and baseline.json accepts them so the gate is not permanently red
// for a reason that is not the product's fault.

import { readFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { PASS, FAIL, UNPROVEN } from '../report.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..', '..', '..')
const SOURCE_REGISTER_PATH = join(REPO_ROOT, 'docs', 'data', 'SOURCE_REGISTER.md')

// The Netlify static origin. Overridable so a preview deploy or a staging
// alias can be checked; a hardcoded default would either lock the case to
// production before production exists, or lock it to a preview URL that stops
// resolving. Leaving it null and baselining the UNPROVEN return is the honest
// state until DOS-M09-007 stands the origin up.
const STATIC_ORIGIN = (process.env.STATIC_ORIGIN || '').replace(/\/+$/, '') || null

// Hosts allowed to appear in the static site's own markup and CSS. The site is
// served from Netlify so its own CDN aliases are unavoidable; the point of the
// case is that nothing else appears — no analytics, no tag manager, no font
// host, no image CDN, no beacon endpoint. INV-27 on the static side of the
// boundary.
const ALLOWED_HOST_PATTERNS = [
  /(^|\.)netlify\.app$/i,
  /(^|\.)netlify\.com$/i,
  /(^|\.)digitaloilsticker\.net$/i,
  /(^|\.)digitaloilsticker\.com$/i,
]

// Static pages to inspect. Every page that ships on the static site should
// appear here; adding a page means adding it here so its copy and its
// referenced hosts are asserted, rather than shipping a page nobody checks.
const STATIC_PAGES = ['/', '/privacy', '/attribution', '/help', '/contact']

const ATTRIBUTION_PATH = '/attribution'

// Words that would imply an account, a server-side backup, or a sync
// relationship — none of which exist on this product. INV-3 (no accounts),
// INV-5 / INV-25 (no implied backup), INV-27 (static site never claims a user
// has an account). Matched as whole word/phrase, case-insensitive, so that
// "no account required" fails the check exactly as "your account" does — if
// the words appear at all, the reader can be misled, and the honest phrasing
// avoids them entirely.
const PROHIBITED_COPY = [
  'sign in',
  'log in',
  'account',
  'your data',
  'sync',
  'backed up',
  'restore',
]

// Single source of truth for the "origin is not stood up" reason, used both
// for the UNPROVEN return and for the matching baseline.json entries. Points
// at the owner action so the reader knows who fixes it, not just that it is
// broken.
const NOT_STOOD_UP =
  'Netlify static origin is not yet reachable via STATIC_ORIGIN. ' +
  'Owner action tracked in DOS-M09-007: cut digitaloilsticker.net DNS to the ' +
  'Netlify team cDiscourse, provision TLS, and publish the marketing, privacy, ' +
  'attribution, help, and contact pages.'

function unavailable(extra) {
  return { status: UNPROVEN, detail: extra ? `${NOT_STOOD_UP} (${extra})` : NOT_STOOD_UP }
}

async function fetchResource(context, url) {
  try {
    const res = await context.request.get(url, { maxRedirects: 5, failOnStatusCode: false })
    const ok = res.ok()
    return { ok, status: res.status(), text: ok ? await res.text() : null }
  } catch (err) {
    return { ok: false, status: 0, text: null, error: err.message }
  }
}

function resolveUrl(base, ref) {
  try {
    return new URL(ref, base).href
  } catch {
    return null
  }
}

function urlsToHosts(urls, baseUrl) {
  const hosts = new Set()
  for (const u of urls) {
    if (!u) continue
    if (/^(?:data:|mailto:|tel:|javascript:|#)/i.test(u)) continue
    const resolved = resolveUrl(baseUrl, u)
    if (!resolved) continue
    try {
      const host = new URL(resolved).hostname
      if (host) hosts.add(host)
    } catch {}
  }
  return hosts
}

function extractHostsFromHtml(html, baseUrl) {
  const urls = new Set()
  const attrRe = /(?:href|src|srcset|action|content|poster|formaction|data-src)\s*=\s*["']([^"']+)["']/gi
  let m
  while ((m = attrRe.exec(html)) !== null) {
    // srcset entries look like "url 1x, url 2x" — split on commas, drop the
    // descriptor after the URL. Non-srcset values still parse fine as a single
    // trimmed token because there is no comma.
    for (const item of m[1].split(',')) {
      const u = item.trim().split(/\s+/)[0]
      if (u) urls.add(u)
    }
  }
  const cssUrlRe = /url\(\s*['"]?([^'")]+?)['"]?\s*\)/gi
  while ((m = cssUrlRe.exec(html)) !== null) urls.add(m[1])
  const importRe = /@import\s+(?:url\(\s*)?['"]([^'"]+)['"]/gi
  while ((m = importRe.exec(html)) !== null) urls.add(m[1])
  return urlsToHosts([...urls], baseUrl)
}

function extractHostsFromCss(css, baseUrl) {
  const urls = new Set()
  const cssUrlRe = /url\(\s*['"]?([^'")]+?)['"]?\s*\)/gi
  let m
  while ((m = cssUrlRe.exec(css)) !== null) urls.add(m[1])
  const importRe = /@import\s+(?:url\(\s*)?['"]([^'"]+)['"]/gi
  while ((m = importRe.exec(css)) !== null) urls.add(m[1])
  return urlsToHosts([...urls], baseUrl)
}

function isAllowedHost(host) {
  return ALLOWED_HOST_PATTERNS.some(re => re.test(host))
}

function stripMarkup(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<[^>]+>/g, ' ')
}

// A source is treated as published — and therefore required on the attribution
// page — when its Review disposition names an approved or published state and
// does NOT still read as a candidate/not-yet-approved seed row. This mirrors
// today's register, where every row is explicitly "candidate — not yet
// approved (DOS-M03-001)"; those must not be listed on the public attribution
// page ahead of the DOS-M03-001 review that approves them. When rows flip to
// approved, this predicate captures them without a schema change.
function isPublishedDisposition(disposition) {
  if (!disposition) return false
  const d = disposition.toLowerCase()
  if (/\bcandidate\b/.test(d)) return false
  if (/not\s+yet\s+approved/.test(d)) return false
  return /\b(approved|published|ratified)\b/.test(d)
}

function parseSourceRegister(text) {
  const lines = text.split(/\r?\n/)
  const published = []
  let inTable = false
  let headers = null
  for (const raw of lines) {
    const line = raw.trim()
    if (!line.startsWith('|')) {
      inTable = false
      headers = null
      continue
    }
    const cells = line
      .replace(/^\|/, '')
      .replace(/\|$/, '')
      .split('|')
      .map(c => c.trim())
    if (cells.length && /^-+:?$/.test(cells[0].replace(/:/g, '-'))) {
      inTable = true
      continue
    }
    if (!headers) {
      headers = cells.map(h => h.toLowerCase())
      continue
    }
    if (!inTable) continue
    const row = Object.fromEntries(headers.map((h, i) => [h, cells[i] ?? '']))
    const source = row['source']
    const disposition = row['review disposition'] ?? ''
    if (!source) continue
    if (isPublishedDisposition(disposition)) published.push(source)
  }
  return published
}

export const cases = [
  {
    id: 'static.reachability',
    requirement: 'FR-18',
    async run({ context }) {
      if (!STATIC_ORIGIN) return unavailable('STATIC_ORIGIN not set')
      const res = await fetchResource(context, STATIC_ORIGIN)
      if (!res.ok) {
        return unavailable(`GET ${STATIC_ORIGIN} responded ${res.status}${res.error ? ` (${res.error})` : ''}`)
      }
      return { status: PASS, evidence: { origin: STATIC_ORIGIN, status: res.status } }
    },
  },

  {
    id: 'static.no-third-party-origins',
    requirement: 'FR-18',
    async run({ context }) {
      if (!STATIC_ORIGIN) return unavailable('STATIC_ORIGIN not set')
      const pagesReached = []
      const foreignByPage = {}

      for (const path of STATIC_PAGES) {
        const pageUrl = `${STATIC_ORIGIN}${path}`
        const page = await fetchResource(context, pageUrl)
        if (!page.ok) continue
        pagesReached.push(path)

        const hosts = new Set(extractHostsFromHtml(page.text, pageUrl))

        // Follow same-origin stylesheets and scan their url()/@import contents
        // too — a third-party font or image loaded from CSS would otherwise
        // slip the HTML-only scan.
        const cssLinks = [...page.text.matchAll(
          /<link[^>]+rel\s*=\s*["']?stylesheet["']?[^>]*>/gi
        )]
          .map(m => {
            const href = /href\s*=\s*["']([^"']+)["']/i.exec(m[0])
            return href ? resolveUrl(pageUrl, href[1]) : null
          })
          .filter(Boolean)

        for (const cssUrl of cssLinks) {
          let cssHost
          try {
            cssHost = new URL(cssUrl).hostname
          } catch {
            continue
          }
          // A third-party CSS URL is already the failure the case is checking
          // for; do not fetch it and give the third party a request that
          // itself would violate INV-27.
          if (!isAllowedHost(cssHost)) continue
          const css = await fetchResource(context, cssUrl)
          if (!css.ok) continue
          for (const h of extractHostsFromCss(css.text, cssUrl)) hosts.add(h)
        }

        const foreign = [...hosts].filter(h => !isAllowedHost(h))
        if (foreign.length) foreignByPage[path] = foreign
      }

      if (!pagesReached.length) {
        return unavailable(`none of ${STATIC_PAGES.join(', ')} returned 2xx`)
      }

      const total = Object.values(foreignByPage).flat().length
      if (total) {
        const summary = Object.entries(foreignByPage)
          .map(([p, hs]) => `${p}: ${hs.join(', ')}`)
          .join(' | ')
        return { status: FAIL, detail: `static pages reference third-party hosts — ${summary}` }
      }
      return { status: PASS, evidence: { pagesReached } }
    },
  },

  {
    id: 'static.no-account-implying-copy',
    requirement: 'FR-18',
    async run({ context }) {
      if (!STATIC_ORIGIN) return unavailable('STATIC_ORIGIN not set')
      const pagesReached = []
      const hitsByPage = {}

      for (const path of STATIC_PAGES) {
        const pageUrl = `${STATIC_ORIGIN}${path}`
        const res = await fetchResource(context, pageUrl)
        if (!res.ok) continue
        pagesReached.push(path)

        const text = stripMarkup(res.text)
        const hits = PROHIBITED_COPY.filter(phrase => {
          const escaped = phrase.replace(/\s+/g, '\\s+')
          return new RegExp(`\\b${escaped}\\b`, 'i').test(text)
        })
        if (hits.length) hitsByPage[path] = hits
      }

      if (!pagesReached.length) {
        return unavailable(`none of ${STATIC_PAGES.join(', ')} returned 2xx`)
      }

      const total = Object.values(hitsByPage).flat().length
      if (total) {
        const summary = Object.entries(hitsByPage)
          .map(([p, hs]) => `${p}: ${hs.join(', ')}`)
          .join(' | ')
        return {
          status: FAIL,
          detail: `static pages contain prohibited account-implying copy — ${summary}`,
        }
      }
      return { status: PASS, evidence: { pagesReached } }
    },
  },

  {
    id: 'static.attribution-matches-source-register',
    requirement: 'FR-18',
    async run({ context }) {
      if (!STATIC_ORIGIN) return unavailable('STATIC_ORIGIN not set')
      if (!existsSync(SOURCE_REGISTER_PATH)) {
        return {
          status: FAIL,
          detail: `docs/data/SOURCE_REGISTER.md not found at ${SOURCE_REGISTER_PATH} — the attribution assertion cannot compare against a missing register`,
        }
      }

      const registerText = readFileSync(SOURCE_REGISTER_PATH, 'utf8')
      const published = parseSourceRegister(registerText)

      const attributionUrl = `${STATIC_ORIGIN}${ATTRIBUTION_PATH}`
      const res = await fetchResource(context, attributionUrl)
      if (!res.ok) {
        return unavailable(`GET ${attributionUrl} responded ${res.status}`)
      }

      const text = stripMarkup(res.text).toLowerCase()
      const missing = published.filter(name => !text.includes(name.toLowerCase()))
      if (missing.length) {
        return {
          status: FAIL,
          detail:
            `attribution page ${attributionUrl} is missing published sources: ` +
            missing.join('; '),
        }
      }
      return {
        status: PASS,
        evidence: {
          attributionUrl,
          publishedInRegister: published.length,
          publishedSources: published,
        },
      }
    },
  },
]
