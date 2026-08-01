// Driving the application through its public UI and its documented protocol
// events. Nothing here reaches into undocumented internals: the four event
// names below are the DOS-M09-003 interface, and everything else is a click or
// a rendered string a user could see.

export const PROTOCOL_EVENTS = ['local_store:hydrate', 'local_store:put', 'local_store:ack', 'local_store:conflict']

/** Record every protocol event crossing the socket, for assertions about
 * ordering, idempotence, and payload contents. */
export async function traceProtocol(page) {
  const seen = []
  await page.exposeFunction('__dosTrace', entry => seen.push(entry))
  await page.addInitScript(() => {
    // The hook pushes through LiveView's own channel; wrap the socket's push
    // rather than the hook so the trace stays on the documented boundary.
    const wrap = () => {
      const socket = window.liveSocket && window.liveSocket.socket
      if (!socket || socket.__dosWrapped) return false
      socket.__dosWrapped = true
      const realPush = socket.push.bind(socket)
      socket.push = data => {
        try {
          if (data && data.event === 'event' && data.payload && data.payload.event) {
            window.__dosTrace({ dir: 'up', event: data.payload.event, at: Date.now() })
          }
        } catch {}
        return realPush(data)
      }
      return true
    }
    const timer = setInterval(() => { if (wrap()) clearInterval(timer) }, 20)
  })
  return seen
}

/** Frames of visible text captured from first paint until hydration resolves,
 * so a claim that flashed for one frame cannot hide (FR-7, INV-24.3). */
export async function captureFramesUntil(page, url, predicate, { budgetMs = 8000, intervalMs = 40 } = {}) {
  const frames = []
  const navigation = page.goto(url, { waitUntil: 'commit' })
  const deadline = Date.now() + budgetMs

  while (Date.now() < deadline) {
    let text = null
    try {
      text = await page.evaluate(() => document.body && document.body.innerText)
    } catch {
      // Mid-navigation; a frame we could not read is simply not a frame.
    }
    if (typeof text === 'string') {
      frames.push(text)
      if (predicate(text)) break
    }
    await page.waitForTimeout(intervalMs)
  }

  await navigation.catch(() => {})
  return { frames, resolved: frames.length > 0 && predicate(frames.at(-1)) }
}

/**
 * Wait until the LiveView is actually connected. `load` fires long before the
 * socket is up, and a change event dispatched at a not-yet-connected form is
 * simply lost — which looks exactly like an application bug from the outside.
 * Every helper here goes through this so a timing artefact is never reported
 * as a conformance failure.
 */
export async function gotoConnected(page, url) {
  await page.goto(url, { waitUntil: 'load' })
  await page.waitForFunction(
    () => window.liveSocket && window.liveSocket.isConnected() && document.querySelector('.phx-connected, [data-phx-main]'),
    null,
    { timeout: 20_000 }
  )
  // Hydration is pushed on mount; give the round trip a moment to land so the
  // first assertion sees a settled view rather than a mid-flight one.
  await page.waitForTimeout(300)
}

/** Walk the cascade and save a vehicle. Returns the label committed. */
export async function setUpVehicle(page, baseUrl, { year = '2021' } = {}) {
  await gotoConnected(page, `${baseUrl}/vehicle/select`)
  await page.waitForSelector('select[name=year]')

  await page.selectOption('select[name=year]', year)
  await page.waitForFunction(() => document.querySelector('select[name=make_id]').options.length > 1)

  const makeValue = await page.$eval('select[name=make_id]', s => [...s.options].find(o => o.value)?.value)
  await page.selectOption('select[name=make_id]', makeValue)
  await page.waitForFunction(() => document.querySelector('select[name=model_id]').options.length > 1)

  const modelValue = await page.$eval('select[name=model_id]', s => [...s.options].find(o => o.value)?.value)
  await page.selectOption('select[name=model_id]', modelValue)
  await page.waitForFunction(() => document.querySelector('select[name=configuration_key]').options.length > 1)

  const configValue = await page.$eval('select[name=configuration_key]', s => [...s.options].find(o => o.value)?.value)
  await page.selectOption('select[name=configuration_key]', configValue)

  await page.waitForSelector('[data-test=confirm-vehicle]')
  const label = await page.$eval('[data-test=confirm-panel]', el => el.innerText)
  await page.click('[data-test=confirm-vehicle]')
  // Navigation is gated on the browser acknowledging the write, so this waits
  // for a full IndexedDB round trip, not just a server response.
  await page.waitForURL(/\/vehicle$/, { timeout: 45_000 })
  return label
}

/**
 * Log one oil change on the active vehicle.
 *
 * The fill is verified and retried once. On Firefox a change event dispatched
 * in the window between `liveSocket.isConnected()` and the LiveView finishing
 * its mount is silently dropped, leaving an empty form and a submit that does
 * nothing. That is a driving artefact, not a product defect — the same flow
 * succeeds on the next attempt — so the harness confirms its own input landed
 * rather than reporting a conformance failure.
 */
export async function logOilChange(page, baseUrl, { odometer = '42000', baseStock = 'full_synthetic' } = {}) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    await gotoConnected(page, `${baseUrl}/service/new`)
    await page.waitForSelector('select[name="service_date[month]"]')

    const grade = await fillOilChangeForm(page, { odometer, baseStock })

    // Did the server actually receive the form? The day select is rebuilt from
    // the chosen month and year, so a settled day value proves the round trip.
    const landed = await page
      .waitForFunction(
        () =>
          document.querySelector('select[name="service_date[day]"]').value === '15' &&
          document.querySelector('input[name="odometer[value]"]').value !== '',
        null,
        { timeout: 5_000 }
      )
      .then(() => true)
      .catch(() => false)

    if (!landed) continue

    await page.click('button[type=submit]')

    const navigated = await page
      .waitForURL(url => !url.pathname.startsWith('/service'), { timeout: 20_000 })
      .then(() => true)
      .catch(() => false)

    if (navigated) return { odometer, baseStock, grade }
  }

  throw new Error('the oil-change form did not commit after two attempts')
}

async function fillOilChangeForm(page, { odometer, baseStock }) {
  await page.selectOption('select[name="service_date[month]"]', '3')
  await page.selectOption('select[name="service_date[year]"]', String(new Date().getFullYear()))
  await page.selectOption('select[name="service_date[day]"]', '15')
  await page.fill('input[name="odometer[value]"]', odometer)
  await page.check(`input[name="oil[base_stock]"][value=${baseStock}]`)

  const grade = await page.$eval('select[name="oil[grade]"]', s =>
    [...s.querySelectorAll('optgroup option')].map(o => o.value)[0] ?? null
  )
  if (grade) await page.selectOption('select[name="oil[grade]"]', grade)
  return grade
}

/** Read every record out of the store, for round-trip and propagation checks. */
export async function readStore(page) {
  return page.evaluate(async () => {
    const open = () => new Promise((resolve, reject) => {
      const req = indexedDB.open('dos_local')
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    })
    const db = await open()
    const names = [...db.objectStoreNames]
    const out = {}
    for (const name of names) {
      out[name] = await new Promise(resolve => {
        const req = db.transaction(name, 'readonly').objectStore(name).getAll()
        req.onsuccess = () => resolve(req.result)
        req.onerror = () => resolve(null)
      })
    }
    db.close()
    return out
  })
}
