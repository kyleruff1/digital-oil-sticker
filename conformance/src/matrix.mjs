// SUPPORT_MATRIX.md is the authority (FR-1). This module reads it rather than
// restating it, so the suite cannot drift from the document: an engine the
// matrix does not list cannot be run, and an engine the matrix lists that the
// suite cannot run is reported unproven instead of quietly dropped (FR-20).

import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ENGINE_DRIVERS = { Chromium: 'chromium', Gecko: 'firefox', WebKit: 'webkit' }

export function loadMatrix(repoRoot) {
  const path = join(repoRoot, 'docs', 'quality', 'SUPPORT_MATRIX.md')
  const text = readFileSync(path, 'utf8')

  const engines = []
  // Rows of the "Engines, not brands" table: | Engine | Ships in | Tier | Host | How |
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\|\s*\*\*(\w+)\*\*\s*\|[^|]*\|\s*(\d)\s*\|([^|]*)\|([^|]*)\|/)
    if (!m) continue
    const [, engine, tier, hostOs, howRaw] = m
    const driver = ENGINE_DRIVERS[engine]
    if (!driver) throw new Error(`matrix names engine ${engine} with no known driver`)

    engines.push({
      key: driver,
      engine,
      tier: Number(tier),
      host_os: hostOs.trim().replace(/\*\*/g, ''),
      // A row that calls itself a proxy is recorded as one; its platform-level
      // results are never presented as the real target's.
      proxy: /proxy/i.test(howRaw) || /proxy/i.test(hostOs),
      proxy_for: /proxy/i.test(hostOs) ? 'Safari on macOS and all iOS browsers' : null,
    })
  }

  if (!engines.length) throw new Error('SUPPORT_MATRIX.md declares no engines')

  const revisionRow = [...text.matchAll(/^\|\s*(\d{4}-\d{2}-\d{2})\s*\|/gm)].at(-1)

  return {
    path,
    revision: revisionRow ? revisionRow[1] : 'unknown',
    engines,
    stalenessDays: Number(text.match(/has not been run in \*\*(\d+) days\*\*/)?.[1] ?? 30),
  }
}
