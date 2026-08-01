#!/usr/bin/env node
// DOS-M00-006: fetch the small, cached, reproducible vPIC (+ FuelEconomy.gov
// candidate) slice. Courteous: serial requests, >=1.2 s spacing, one retry.
// Raw responses are preserved verbatim under fixtures/raw/ with an envelope
// recording url, retrieved_at, HTTP status, and the SHA-256 of the raw body —
// the downstream import (import.mjs) reads ONLY these cached files.
//
// Green lane: official U.S. government structured data (17 U.S.C. §105).
// Requests span several model years, makes, ambiguous trims, deliberate
// missing fields, an EV (not_applicable), and discontinued/renamed makes.

import { writeFileSync, mkdirSync } from 'node:fs'
import { createHash } from 'node:crypto'

const RAW = new URL('./fixtures/raw/', import.meta.url)
mkdirSync(RAW, { recursive: true })

const sleep = ms => new Promise(r => setTimeout(r, ms))

// Public sample VINs (NHTSA documentation example + widely published samples).
// None belong to a private individual's record; VIN decode is structural.
const VINS = [
  ['5UXWX7C5XBA', 'bmw-x3-2011-partial'],        // NHTSA API docs example (partial VIN → missing fields)
  ['1FTFW1ET5DFC10312', 'ford-f150-2013'],       // widely published sample
  ['5YJ3E1EA7KF317621', 'tesla-model3-2019'],    // EV → engine-oil not_applicable evidence
  ['4T1BF1FK5HU999999', 'toyota-camry-2017-checkdigit'], // synthetic tail → error/missing handling
]

const REQUESTS = [
  ['vpic-variable-list', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetVehicleVariableList?format=json'],
  // Model-year coverage across the rolling window (1997 baseline start, mid, current)
  ['vpic-models-toyota-1997', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/toyota/modelyear/1997?format=json'],
  ['vpic-models-toyota-2024', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/toyota/modelyear/2024?format=json'],
  ['vpic-models-ford-2010', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/ford/modelyear/2010?format=json'],
  ['vpic-models-honda-2024', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/honda/modelyear/2024?format=json'],
  ['vpic-models-bmw-2015', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/bmw/modelyear/2015?format=json'],
  ['vpic-models-tesla-2024', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/tesla/modelyear/2024?format=json'],
  // Discontinued make: active years vs post-discontinuation (expect empty)
  ['vpic-models-pontiac-2008', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/pontiac/modelyear/2008?format=json'],
  ['vpic-models-pontiac-2024', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/pontiac/modelyear/2024?format=json'],
  // Renamed/spun-off make: Ram trucks split from Dodge around 2010
  ['vpic-models-dodge-2009', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/dodge/modelyear/2009?format=json'],
  ['vpic-models-ram-2024', 'https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/ram/modelyear/2024?format=json'],
  ...VINS.map(([vin, slug]) => [`vpic-vin-${slug}`, `https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValuesExtended/${vin}?format=json`]),
  // FuelEconomy.gov free-candidate probe: configuration enrichment shape (XML)
  ['feg-menu-options-2020-toyota-camry', 'https://www.fueleconomy.gov/ws/rest/vehicle/menu/options?year=2020&make=Toyota&model=Camry'],
  ['feg-menu-models-1997-toyota', 'https://www.fueleconomy.gov/ws/rest/vehicle/menu/model?year=1997&make=Toyota'],
]

const manifest = []
for (const [name, url] of REQUESTS) {
  let attempt = 0, res, body
  for (;;) {
    try {
      res = await fetch(url, { headers: { 'User-Agent': 'digital-oil-sticker-m00-006-spike (research slice; contact: repo owner)' } })
      body = await res.text()
      break
    } catch (e) {
      if (attempt++ >= 1) throw e
      await sleep(5000)
    }
  }
  const sha256 = createHash('sha256').update(body, 'utf8').digest('hex')
  const retrieved_at = new Date().toISOString()
  writeFileSync(new URL(`${name}.body`, RAW), body, 'utf8')
  writeFileSync(new URL(`${name}.meta.json`, RAW), JSON.stringify({ name, url, status: res.status, retrieved_at, sha256, content_type: res.headers.get('content-type') }, null, 2) + '\n', 'utf8')
  manifest.push({ name, url, status: res.status, retrieved_at, sha256 })
  console.log(`${res.status} ${name} sha=${sha256.slice(0, 12)}`)
  await sleep(1200)
}
writeFileSync(new URL('./fixtures/manifest.json', import.meta.url), JSON.stringify({ generator: 'spikes/m00-006-data-boundary/fetch.mjs', request_count: manifest.length, requests: manifest }, null, 2) + '\n', 'utf8')
console.log(`\n${manifest.length} responses cached under spikes/m00-006-data-boundary/fixtures/raw/`)
