// FuelEconomy.gov adapters (DOS-M03-005 FR-7). Primary source is the bulk
// vehicles.csv (one request; strict superset of menu/options with the same
// integer id space — owner-approved substitution 2026-08-01). The menu
// endpoints are used only as a small sampled verification probe.

const CSV_URL = 'https://www.fueleconomy.gov/feg/epadata/vehicles.csv'
const WS = 'https://www.fueleconomy.gov/ws/rest/vehicle/menu'

export const WINDOW_START = 1997
export const WINDOW_END = 2026

export async function fetchBulkCsv(client) {
  const { body, meta } = await client.fetchCached('feg-vehicles-csv', CSV_URL, { accept: '*/*' })
  return { csv: body, meta }
}

// Minimal RFC-4180 CSV parser (quoted fields, embedded commas/quotes/newlines).
export function parseCsv(text) {
  const rows = []
  let row = [], field = '', inQuotes = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++ } else inQuotes = false
      } else field += c
    } else if (c === '"') inQuotes = true
    else if (c === ',') { row.push(field); field = '' }
    else if (c === '\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row = []; field = '' }
    else field += c
  }
  if (field !== '' || row.length) { row.push(field.replace(/\r$/, '')); rows.push(row) }
  return rows
}

export function bulkRowsInWindow(csvText) {
  const rows = parseCsv(csvText)
  const header = rows[0]
  const idx = Object.fromEntries(header.map((h, i) => [h, i]))
  const need = ['id', 'year', 'make', 'model', 'baseModel', 'cylinders', 'displ', 'drive', 'fuelType1', 'eng_dscr', 'trany', 'trans_dscr', 'VClass', 'atvType', 'startStop', 'fuelType2']
  for (const c of ['id', 'year', 'make', 'model', 'baseModel']) {
    if (!(c in idx)) throw new Error(`vehicles.csv missing required column ${c}`)
  }
  const out = []
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i]
    if (r.length < 2) continue
    const year = Number(r[idx.year])
    if (!Number.isInteger(year) || year < WINDOW_START || year > WINDOW_END) continue
    const rec = {}
    for (const c of need) rec[c] = c in idx ? r[idx[c]] : ''
    rec.year = year
    rec.id = Number(rec.id)
    out.push(rec)
  }
  return out
}

export async function fetchMenuOptionsProbe(client, year, make, model) {
  const name = `feg-menu-options-${year}-${slug(make)}-${slug(model)}`
  const url = `${WS}/options?year=${year}&make=${encodeURIComponent(make)}&model=${encodeURIComponent(model)}`
  const { body } = await client.fetchCached(name, url, { accept: 'application/json' })
  try {
    const j = JSON.parse(body)
    const items = Array.isArray(j.menuItem) ? j.menuItem : j.menuItem ? [j.menuItem] : []
    return items.map(m => ({ text: m.text, value: Number(m.value) }))
  } catch {
    // XML fallback (default response when Accept is not honored from cache of the spike era)
    return [...body.matchAll(/<value>(\d+)<\/value>/g)].map(m => ({ text: null, value: Number(m[1]) }))
  }
}

function slug(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
}
