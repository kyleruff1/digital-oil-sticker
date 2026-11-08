# Grok Deep Research Prompt: Automotive POS/DMS Integration Contacts

> Paste this into grok.ai using DeepSearch mode.

---

## The research request

I am building **Digital Oil Sticker** (digitaloilsticker.com), a free, open, read-only API that returns a vehicle's next-service QR code in multiple output schemas so that any automotive POS, DMS, CRM, or shop-management system can embed it in their existing print workflow — regular inkjet, laser, or thermal receipt/label printers. No proprietary hardware. No per-shop subscription. No authentication required for the read endpoint.

I need you to find **people, companies, roles, and consultants** who can help me build relationships to pitch this integration to the systems that matter. This is a business-development and channel-strategy research request, not a technical one.

---

## What I am building (so you understand the pitch)

- A **public, no-auth, read-only REST API** that accepts a vehicle identifier + service data and returns a QR code payload.
- The QR code encodes the vehicle's next-service due date, due mileage, oil grade, and a deep link back to the vehicle's record in the consumer-facing Digital Oil Sticker PWA.
- The API returns the QR code in **multiple schema shapes**: raw PNG/SVG image bytes, base64-encoded data URIs, ZPL (Zebra thermal printer language), ESC/POS (thermal receipt printers), EPL, PDF label layouts, and structured JSON for systems that want to render their own.
- The integration pattern is deliberately zero-friction: a shop-management system calls one endpoint after closing a work order, gets back a print-ready sticker payload, and sends it to whatever printer is already on the counter. No new hardware. No SDK. No OAuth dance.
- The consumer-facing app is a privacy-first PWA (no accounts, IndexedDB-only, no server-side personal data).

## The competitive landscape I already know about

### My Oil Sticker (myoilsticker.com)
- Founded by unknown (possibly connected to a company called "DigitalDog" — need confirmation).
- Prints full-color branded stickers on a **proprietary ZINK printer** (Brother VC-500W). Requires shops to buy the printer (~$495 starter kit) and proprietary ZINK label rolls (ongoing consumable cost).
- Software subscription is **$79.95/month** per shop.
- Integrations listed: **Tekmetric, Shopmonkey, Shop-Ware, Protractor, Autoflow**.
- QR code links to an appointment-scheduling page.
- This is the most direct competitor. Their weakness is the proprietary hardware lock-in and per-shop subscription cost.

### Steer CRM (steercrm.com)
- **Gregg Rainville**, Senior VP, appeared on the **NOLN Podcast** (January 2026, "Reimagining the Oil Change Reminder Sticker") discussing Steer's digital oil sticker with QR codes showing service wait times and vehicle service history.
- Steer is a CRM platform, so their sticker is part of a larger CRM upsell, not a standalone product.
- Key person to track: Gregg Rainville (SVP at Steer, frequent NOLN podcast guest, positioned as a thought leader in quick-lube digital innovation).

### SAF-T Oil Sticker Generator
- Chrome extension for **Shop-Ware** users only.
- Extracts mileage from work orders, generates a QR code + shop branding on a sticker.
- Very narrow: one SMS platform, browser-only, no API.

### Orderry
- Ties sticker printing to its own POS. Closed ecosystem.

---

## The integration targets I need introductions to

These are the shop-management, DMS, and POS platforms whose integration/partner programs I want to join. For each, I need you to find:

1. **The person who runs their integration/partner program** (title like "Head of Integrations," "VP Partnerships," "Developer Relations," "Partner Ecosystem Manager").
2. **Any public-facing developer advocate or API evangelist** at the company.
3. **Anyone on X/Twitter or LinkedIn who has publicly discussed building integrations with that platform.**

### Tier 1 — Independent shop-management (aftermarket, quick-lube)
- **Tekmetric** — Already has My Oil Sticker as a listed integration partner. Who approved that? Who manages the Tekmetric integration marketplace?
- **Shopmonkey** — Same question. They list oil stickers as a feature. Who runs their partner program?
- **Shop-Ware** — SAF-T already has a Chrome extension for it. Who manages their third-party integrations?
- **Mitchell1 / Manager SE** — Long-established. Who is their current integration/partnership lead?
- **AutoLeap** — Has a documented "Partner API" with token-based auth. Who manages it?
- **Protractor** — My Oil Sticker lists it as an integration. Who is the partnership contact?
- **Autoflow** — Same as above.

### Tier 2 — Franchise and dealership DMS
- **CDK Global (CDK Drive)** — Dominant in franchise dealerships. What is their current partner/API program called, and who leads it?
- **Cox Automotive / Dealertrack DMS** — Has the **Opentrack** integration program. Who is the program manager?
- **Tekion** — Has the **Automotive Partner Cloud**. Who runs it?
- **Dominion DMS (VUE)** — Has a service-department API suite. Who manages partner onboarding?
- **Reynolds and Reynolds** — Historically closed, but has a partner program. Current status and contacts?

### Tier 3 — Middleware / integration platforms
- **Motive Retail (MIX)** — This is the "integrate once, connect to many" middleware layer. They claim 120+ integrated vendors. Who is the business-development or partner-onboarding contact? This might be the single highest-leverage relationship because one MIX integration could reach Dealertrack, Tekion, AutoSoft, and others simultaneously.
- **PartsTech** — Lists Mitchell1 and Shop-Ware among its management-system partners. Has "Advanced API capabilities for partners."
- **Supergood.ai** — Builds unofficial API adapters for Tekmetric, Shopmonkey, Shop-Ware, AutoSoft. Small company, but they clearly know the integration surface of every major SMS.

---

## The consultants and advisors I am looking for

Find people who fit any of these profiles:

### 1. Automotive aftermarket integration consultants
People or firms who have helped SaaS vendors get their product integrated into shop-management platforms. They understand the partner-program application process, the technical certification requirements, and the business-development side of getting listed in an integration marketplace.

### 2. Quick-lube and oil-change industry insiders
People who work in or consult for the quick-lube segment (Jiffy Lube, Valvoline Instant Oil Change, Take 5, independent quick-lubes) and would know which systems those shops actually use and what the pain points are with current oil-change sticker solutions.

### 3. Automotive technology journalists and podcast hosts
People who cover the aftermarket technology space and could amplify the "free, open API vs. proprietary hardware lock-in" story. Starting points:
- **NOLN (National Oil and Lube News)** — Who is the editor/host? They already covered this exact topic with Gregg Rainville.
- **Ratchet+Wrench** — Covers independent shop technology.
- **Auto Service Professional / Underhood Service** — Trade press.

### 4. Thermal printer and label integration specialists
People or companies who specialize in ZPL/ESC/POS label printing integration for point-of-sale environments. The pitch is that Digital Oil Sticker works with the thermal printer the shop already owns (Star, Epson, Zebra, Brother) instead of requiring a new proprietary device.

---

## What I want Grok to deliver

For each person or company you find, provide:
- **Full name and current title/role**
- **Company**
- **Why they are relevant** (one sentence)
- **X/Twitter handle** (if they have one)
- **LinkedIn URL** (if findable)
- **Any recent public posts or articles** about DMS/SMS integrations, oil-change technology, or the quick-lube industry

Organize the results into these sections:
1. **Integration/Partnership Program Leads** (by platform)
2. **Middleware and API Specialists**
3. **Industry Consultants and Advisors**
4. **Journalists and Amplifiers**
5. **Thermal Printing / Label Integration Contacts**

For each section, also note any **conferences, trade shows, or industry events** in 2026-2027 where these people are likely to be (AAPEX, SEMA, NACE, Oil & Lube Expo, etc.).

---

## Key talking points for my pitch (context for Grok to understand what is differentiated)

| | My Oil Sticker | Digital Oil Sticker |
|---|---|---|
| **Printer** | Proprietary ZINK (Brother VC-500W) | Any printer the shop already owns |
| **Consumables** | Proprietary ZINK rolls | Standard labels or thermal paper |
| **Shop cost** | $495 setup + $79.95/mo | Free (open API) |
| **Auth** | Per-shop account required | No auth on read endpoint |
| **Integration effort** | Per-platform custom integration | One REST call, multiple output schemas |
| **QR payload** | Appointment scheduling link | Full vehicle service record deep link |
| **Consumer data** | Unknown (hosted service) | Zero server-side personal data (browser-only) |
| **Business model** | SaaS subscription | Consumer-facing PWA (sticker API is the distribution channel) |

The pitch to a shop-management platform is: "We are the open, free alternative your shops are asking for. One API call after work-order close. No new hardware for the shop to buy. No subscription for you to collect or support. Your integration marketplace gets a sticker solution that costs your customers nothing."
