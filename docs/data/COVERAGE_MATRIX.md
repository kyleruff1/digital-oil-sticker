# Coverage Matrix

Status: **planning default — the coverage contract below holds until M00 approves a different matrix.** Measured coverage is produced by DOS-M03-010 (deterministic offline catalog release) and recorded in the tables at the end of this document.

## Coverage contract (planning default frozen in M00)

- Market: United States.
- Rolling window: 30 model years; for the 2026 baseline, 1997–2026 inclusive.
- Vehicle classes: passenger cars, multipurpose passenger vehicles, and light pickups/vans that use engine oil.
- Include gasoline, diesel, and hybrid configurations when a licensed source supports them.
- Pure battery-electric vehicles may appear for honest identification but show "engine oil service not applicable"; never invent an oil plan.
- Heavy commercial vehicles, motorcycles, powersports, off-highway equipment, and non-U.S. schedules are excluded from v1.
- Catalog presence and recommendation support are separate statuses: `identity_only`, `schedule_supported`, `full_product_supported`, `not_applicable`, and `unsupported`.

## Initial coverage targets: fact-domain and free-candidate matrix

M03 must investigate this free candidate matrix before opening a commercial procurement ticket, and must measure and reconcile these sources rather than forcing any one to supply facts it does not contain.

| Fact domain | Free/public candidates to test first | Intended use and hard limit |
| --- | --- | --- |
| Year/make/model/vehicle type and VIN-coded attributes | [NHTSA vPIC API](https://vpic.nhtsa.dot.gov/api/) | Identity spine and aliases; not complete retail configurations and no maintenance facts. |
| U.S. engine/fuel/drive/transmission configuration clues | [FuelEconomy.gov bulk data and web services](https://www.fueleconomy.gov/feg/download.shtml); [EPA annual light-duty certification/test files](https://www.epa.gov/compliance-and-fuel-economy-data/annual-certification-data-vehicles-engines-and-equipment) | Configuration enrichment, reconciliation, and QA; never oil/filter recommendations. |
| OEM time/distance/condition intervals and oil requirements | Public OEM owner manuals, maintenance guides, warranty/maintenance booklets, and manufacturer service portals that permit the acquisition method | Extract discrete, cited facts into an original schema; do not copy protected prose/layout/assets. Coverage and version matching must be measured configuration by configuration. |
| Oil product identity and published claims | [API EOLCS directory](https://www.api.org/products-and-services/engine-oil/eolcs-licensee-directory); brand technical/product data sheets; certification/license lists offered for download or documented lookup | Verify a specific SKU's published claims and effective status. Certification/viscosity alone does not establish vehicle compatibility or an interval. |
| Oil-filter application | Filter-maker/supplier downloadable application guides, public structured feeds, or written-permission exports | Exact part-to-configuration fitment plus qualifiers only. A brand, dimensions alone, or unlicensed aggregator cross-reference is insufficient. |
| Names, aliases, and QA cross-checks | vPIC manufacturer/make/model/variable endpoints; EPA/DOE files; NHTSA datasets where relevant | Normalization and anomaly detection; never infer a missing maintenance or fitment fact. |

Additional source-limit notes:

- The [vPIC standalone downloads](https://vpic.nhtsa.dot.gov/Downloads) are explicitly limited to VIN-decoding functionality; they do not replace catalog API calls and should not be embedded merely to create a year/make/model selector.
- vPIC has no engine-oil interval, viscosity, oil capacity, oil-product, or filter-fitment fields. It is the vehicle-identity spine only.

## Measured coverage (to be filled by DOS-M03-010)

The catalog builder emits coverage counts per `data_version`. DOS-M03-010 populates these tables from the build report; do not fill them by hand or by estimate.

### Identity coverage by model year

| Model year | Configurations in catalog | `identity_only` | `schedule_supported` | `full_product_supported` | `not_applicable` | `unsupported` |
| --- | --- | --- | --- | --- | --- | --- |
| _pending DOS-M03-010_ | | | | | | |

### Fact-domain coverage by source

| Fact domain | Source (register entry) | Configurations covered | Configurations in scope | Coverage | Notes |
| --- | --- | --- | --- | --- | --- |
| _pending DOS-M03-010_ | | | | | |

### Reconciliation and conflict summary

| Fact domain | Sources compared | Agreements | Conflicts retained for review | Rejected rows | Notes |
| --- | --- | --- | --- | --- | --- |
| _pending DOS-M03-010_ | | | | | |
