# Licensing and Rights Checklist

Every fact domain in the shipped catalog must clear the checklist for its lane before DOS-M03-001 can approve the source. Record the outcome of each item in `docs/data/SOURCE_REGISTER.md`. Ambiguous sources stay out of a shipped catalog until reviewed.

## Green lane — official U.S. government structured data

Applies to vPIC, FuelEconomy.gov, and EPA certification downloads/APIs. Under [17 U.S.C. §105](https://www.copyright.gov/title17/92chap1.html), copyright protection generally is not available for U.S. Government works.

- [ ] Official source captured (agency, dataset name, canonical URL).
- [ ] Access instructions captured (API documentation or download procedure).
- [ ] Agency disclaimer and attribution requirements captured.
- [ ] Data revision recorded.
- [ ] Any third-party notices inside the dataset identified.
- [ ] Factual fields presumptively approved when no contrary restriction appears.
- [ ] Escalated **only** for: a marked third-party work, a trademark/endorsement concern, a privacy issue, or contradictory terms — not the mere fact that the data is free.

## Documented-facts lane — public OEM and product documents

Applies to owner manuals, maintenance booklets, warranty/maintenance guides, oil-product technical data sheets, certification listings, and supplier application files.

- [ ] Discrete facts normalized into the project's original schema; original UI wording written.
- [ ] No vendored source PDFs, protected images, prose, or table layouts.
- [ ] Document/version/page or field provenance recorded for every extracted fact.
- [ ] Publisher's access/automation terms recorded; acquisition method complies with them.
- [ ] Manual acquisition used where automated retrieval is not permitted.
- [ ] Extraction-queue record complete: document URL, revision, market, model/configuration applicability, page/section locator, extracted factual value, reviewer, checksum.
- [ ] Only fields the rights matrix permits are stored.

## Permission-needed lane — bulk extraction from interactive commercial sites

Applies to freely viewable locators or catalogs (for example filter finders) that may still prohibit automated extraction or redistribution.

- [ ] An offered download/API, written permission, or a supplier-provided file exists — or the domain stays manual/unsupported.
- [ ] "Visible without a login" has **not** been treated as permission for automated extraction and redistribution.
- [ ] No scraping of OEM, oil-brand, or filter-brand product finders whose terms prohibit it.
- [ ] Exact terms/license, access method, attribution, factual fields used, and legal/product review disposition recorded in the source register.
- [ ] If no permitted path exists, procurement covers only the measured gap.

## One-time-snapshot procurement requirements (commercial gaps)

For gaps that free sources cannot cover, the preferred procurement is a **one-time bulk snapshot with perpetual rights to normalize, vendor, and redistribute that acquired version inside the offline application**. Paying for API access or receiving a data file is not enough by itself. Written terms must permit **all** of the following:

- [ ] Consumer-app use.
- [ ] Caching.
- [ ] Normalized derivatives.
- [ ] Offline end-user storage.
- [ ] Inclusion in signed build/catalog artifacts.
- [ ] Internal backups and historical snapshots.
- [ ] Required attribution/trademark treatment (documented and implementable).
- [ ] Continued distribution of the already-acquired version after the commercial relationship ends.

Additionally:

- [ ] Optional refresh purchases or a subscription are priced and planned separately.
- [ ] The installed app does not depend on an ongoing provider API.
