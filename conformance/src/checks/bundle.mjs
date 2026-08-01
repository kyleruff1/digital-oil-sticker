// Static assertions about the SHIPPED client bundle (FR-4, FR-22).
//
// These run against the built asset the browser actually downloads, not the
// source tree, because the question is what reaches the user. A source file
// could be clean while a dependency or a build step reintroduces the thing.

import { PASS, FAIL, UNPROVEN } from '../report.mjs'

// User-agent sniffing. `navigator.userAgent` appearing at all is the signal:
// the app is required to decide by capability probe, so there is no legitimate
// reason for the string to be read in our own code.
const UA_PATTERNS = [
  /navigator\s*\.\s*userAgent/,
  /navigator\s*\.\s*userAgentData/,
  /navigator\s*\.\s*vendor\b/,
  /navigator\s*\.\s*platform\b/,
]

// Deferred capabilities (INV-6, INV-17, INV-19). Their presence would silently
// change what the app promises about working offline and notifying people.
const DEFERRED_PATTERNS = [
  { id: 'service-worker', re: /serviceWorker\s*\.\s*register/ },
  { id: 'push', re: /pushManager|PushSubscription/ },
  { id: 'background-sync', re: /\bsync\s*\.\s*register\s*\(|SyncManager/ },
]

export async function fetchBundles(page, baseUrl) {
  await page.goto(baseUrl, { waitUntil: 'load' })

  const urls = await page.evaluate(() =>
    [...document.querySelectorAll('script[src]')].map(s => s.src)
  )

  const sources = []
  for (const url of urls) {
    // Only our own origin's assets; a third-party script would be a separate
    // and much louder failure, caught by the privacy case.
    if (!url.startsWith(new URL(baseUrl).origin)) continue
    const body = await page.evaluate(async u => {
      const res = await fetch(u)
      return res.ok ? res.text() : null
    }, url)
    if (body) sources.push({ url, body })
  }
  return sources
}

export function userAgentBranching(sources) {
  if (!sources.length) {
    return { status: UNPROVEN, detail: 'no first-party script bundle could be fetched, so it was not scanned' }
  }

  const hits = []
  for (const { url, body } of sources) {
    for (const re of UA_PATTERNS) {
      if (re.test(body)) hits.push(`${url} matches ${re}`)
    }
  }

  return hits.length
    ? { status: FAIL, detail: `client bundle reads the user agent: ${hits.join('; ')}` }
    : { status: PASS, evidence: { scanned: sources.map(s => s.url) } }
}

export function deferredCapabilities(sources) {
  if (!sources.length) {
    return { status: UNPROVEN, detail: 'no first-party script bundle could be fetched, so it was not scanned' }
  }

  const hits = []
  for (const { url, body } of sources) {
    for (const { id, re } of DEFERRED_PATTERNS) {
      if (re.test(body)) hits.push(`${id} in ${url}`)
    }
  }

  return hits.length
    ? { status: FAIL, detail: `deferred capability present in the shipped client: ${hits.join('; ')}` }
    : { status: PASS, evidence: { scanned: sources.map(s => s.url) } }
}

/** A manifest link is markup, not script, so it is checked on the page. */
export async function manifestAbsent(page) {
  const links = await page.evaluate(() =>
    [...document.querySelectorAll('link[rel~="manifest"]')].map(l => l.getAttribute('href'))
  )
  return links.length
    ? { status: FAIL, detail: `web app manifest linked: ${links.join(', ')}` }
    : { status: PASS }
}

/** Nothing may be registered at runtime either. */
export async function noRuntimeServiceWorker(page) {
  const registered = await page.evaluate(async () => {
    if (!navigator.serviceWorker) return []
    const regs = await navigator.serviceWorker.getRegistrations()
    return regs.map(r => r.scope)
  })
  return registered.length
    ? { status: FAIL, detail: `service worker registered at runtime: ${registered.join(', ')}` }
    : { status: PASS }
}
