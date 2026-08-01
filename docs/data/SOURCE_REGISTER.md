# Source Register

Every data source that contributes a fact to the shipped catalog must have a row here **before** its facts appear in any artifact. No displayed manufacturer interval, viscosity/specification, capacity, oil-product claim, or filter fitment ships without provenance and a license permitting offline redistribution. Ambiguous sources stay out of a shipped catalog until reviewed.

Status of this document: **seed register — every entry below is a candidate, not an approval.** Approval happens in DOS-M03-001 (data-source and redistribution rights matrix).

## Register structure

Each entry records these columns:

| Column | Meaning |
| --- | --- |
| Source | Provider and dataset/document name |
| Type | Government API/dataset, OEM document, certification directory, supplier guide, commercial product |
| Lane | `green`, `documented-facts`, or `permission-needed` (see the three-lane model below) |
| URL | Canonical URL or document locator |
| License/terms | Exact license reference or terms captured verbatim/by locator |
| Access method | Documented API, bulk download, manual reviewed extraction, written-permission export |
| Fields used | The specific factual fields this source is allowed to supply |
| Attribution | Required attribution text/treatment |
| Review disposition | Legal/product review status |
| Retrieved/verified | Retrieval and verification timestamps (recorded at acquisition time) |
| Checksum | SHA-256 of the acquired file/document snapshot |

## Three-lane approval model

Apply a pragmatic three-lane approval model so rights diligence does not become an excuse to buy data unnecessarily. Use a free-first, field-by-field acquisition strategy: do not reject a source merely because it is free, and do not purchase fields already covered by an acceptable source.

1. **Green lane — official U.S. government structured data.** Start with vPIC, FuelEconomy.gov, and EPA certification downloads/APIs. Under [17 U.S.C. §105](https://www.copyright.gov/title17/92chap1.html), copyright protection generally is not available for U.S. Government works. Capture the official source, access instructions, agency disclaimer/attribution, data revision, and any third-party notices, then presumptively approve factual fields when no contrary restriction appears. Escalate only a marked third-party work, a trademark/endorsement concern, a privacy issue, or contradictory terms — not the mere fact that the data is free.
2. **Documented-facts lane — public OEM and product documents.** Evaluate owner manuals, maintenance booklets, warranty/maintenance guides, oil-product technical data sheets, certification listings, and supplier application files. Normalize discrete facts and write original UI wording; do not vendor source PDFs, protected images, prose, or table layouts. Record document/version/page or field provenance plus the publisher's access/automation terms. Manual acquisition is permitted when automated retrieval is not.
3. **Permission-needed lane — bulk extraction from interactive commercial sites.** A freely viewable locator or catalog may still prohibit automated extraction or redistribution. Prefer an offered download/API, written permission, or a supplier-provided file. If none exists, keep that domain manual/unsupported or procure only the measured gap.

Do not equate "visible without a login" with permission for automated extraction and redistribution. Do not scrape OEM, oil-brand, or filter-brand product finders whose terms prohibit it.

## Seed entries (free/public candidate matrix)

| Source | Type | Lane | URL | License/terms | Access method | Fields used | Attribution | Review disposition | Retrieved/verified | Checksum |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| NHTSA vPIC API | Government API | green | https://vpic.nhtsa.dot.gov/api/ | U.S. Government work presumption (17 U.S.C. §105); capture agency disclaimer at approval | Documented public API | Year/make/model, vehicle type, VIN-coded attributes, manufacturer/make/model/variable endpoints; identity spine and aliases only — not complete retail configurations, no maintenance facts | NHTSA/vPIC, per agency guidance | candidate — not yet approved (DOS-M03-001) | pending | pending |
| NHTSA vPIC standalone downloads | Government dataset | green | https://vpic.nhtsa.dot.gov/Downloads | Same as vPIC API; downloads are explicitly limited to VIN-decoding functionality | Bulk download | VIN-decoding support only; must not be embedded merely to create a year/make/model selector | NHTSA/vPIC, per agency guidance | candidate — not yet approved (DOS-M03-001) | pending | pending |
| EPA/DOE FuelEconomy.gov bulk vehicle data | Government dataset + web services | green | https://www.fueleconomy.gov/feg/download.shtml | U.S. Government work presumption (17 U.S.C. §105); capture disclaimer at approval | Bulk download and documented web services | U.S. engine/fuel/drive/transmission configuration clues (1984–current); configuration enrichment, reconciliation, and QA; never oil/filter recommendations | EPA/DOE FuelEconomy.gov | candidate — not yet approved (DOS-M03-001) | pending | pending |
| EPA annual vehicle and engine certification data | Government dataset | green | https://www.epa.gov/compliance-and-fuel-economy-data/annual-certification-data-vehicles-engines-and-equipment | U.S. Government work presumption (17 U.S.C. §105); capture disclaimer at approval | Bulk download | Light-duty certified-vehicle model and test-result files; engine/configuration cross-checks and QA; never oil/filter recommendations | EPA | candidate — not yet approved (DOS-M03-001) | pending | pending |
| Public OEM owner manuals, maintenance guides, warranty/maintenance booklets, and manufacturer service portals | OEM documents | documented-facts | Per-document locators recorded at extraction time | Per-publisher terms; only portals that permit the acquisition method | Reproducible human-reviewed extraction queue (see below); manual acquisition when automation is not permitted | OEM time/distance/condition intervals and oil requirements as discrete, cited facts in an original schema; no copied prose/layout/assets; coverage and version matching measured configuration by configuration | Per-document provenance shown in-app | candidate — not yet approved (DOS-M03-001) | pending | pending |
| API EOLCS licensee directory | Certification directory | documented-facts | https://www.api.org/products-and-services/engine-oil/eolcs-licensee-directory | API terms; capture at approval | Documented lookup or offered download | Verify a specific SKU's published claims and effective license status; certification/viscosity alone does not establish vehicle compatibility or an interval; does not map a product to a vehicle | American Petroleum Institute | candidate — not yet approved (DOS-M03-001) | pending | pending |
| Oil-brand technical/product data sheets and downloadable certification lists | Product documents | documented-facts | Per-document locators recorded at extraction time | Per-publisher terms | Download or manual reviewed extraction | Oil product identity and published claims (viscosity, certifications, approvals) | Per-brand as required | candidate — not yet approved (DOS-M03-001) | pending | pending |
| Filter-maker application guides — WIX Filter Finder | Supplier guide/locator | permission-needed | https://www.wixfilters.com/en-us/filter-finder.html | Terms review required; interactive finders may prohibit bulk extraction | Offered download/API, written permission, or supplier-provided file only | Exact part-to-configuration fitment plus qualifiers; brand, dimensions alone, or unlicensed aggregator cross-reference is insufficient | Per supplier terms | candidate — not yet approved (DOS-M03-001) | pending | pending |
| Filter-maker application guides — Purolator Part Finder | Supplier guide/locator | permission-needed | https://www.purolatornow.com/en/part-finder.html | Terms review required; interactive finders may prohibit bulk extraction | Offered download/API, written permission, or supplier-provided file only | Exact part-to-configuration fitment plus qualifiers | Per supplier terms | candidate — not yet approved (DOS-M03-001) | pending | pending |
| Filter-maker application guides — FRAM online catalog | Supplier guide/locator | permission-needed | https://www.fram-europe.com/en/catalogue/online-catalogue.html | Terms review required; interactive finders may prohibit bulk extraction | Offered download/API, written permission, or supplier-provided file only | Exact part-to-configuration fitment plus qualifiers | Per supplier terms | candidate — not yet approved (DOS-M03-001) | pending | pending |

## Commercial procurement fallbacks (only for measured gaps)

M03 must investigate the free candidate matrix above before opening a commercial procurement ticket. If measured gaps remain, candidates include:

| Source | Type | URL | Notes | Review disposition |
| --- | --- | --- | --- | --- |
| MOTOR Maintenance Schedules | Commercial data product | https://www.motor.com/products-services/data-products/maintenance-schedules/ | OEM-derived maintenance schedules | candidate — not yet approved (DOS-M03-001) |
| MOTOR Fluids | Commercial data product | https://www.motor.com/products-services/data-products/fluids/ | OEM-derived fluids data | candidate — not yet approved (DOS-M03-001) |
| Auto Care ACES | Exchange standard | https://www.autocare.org/aces | Fitment exchange standard; ACES and VCdb do not themselves grant a parts catalog | candidate — not yet approved (DOS-M03-001) |

The preferred procurement shape for any gap is a one-time bulk snapshot with perpetual rights to normalize, vendor, and redistribute the acquired version inside the offline application. See `docs/data/LICENSING_CHECKLIST.md` for the full written-terms requirements.

## Extraction-queue record (documented-facts lane)

For public manuals and data sheets, prefer a reproducible human-reviewed extraction queue over indiscriminate crawling. Each queue record captures:

- document URL;
- revision;
- market;
- model/configuration applicability;
- page/section locator;
- extracted factual value;
- reviewer;
- checksum.

Store only what the rights matrix permits. This gives the project a credible no-license path even if automated bulk access is unavailable.
