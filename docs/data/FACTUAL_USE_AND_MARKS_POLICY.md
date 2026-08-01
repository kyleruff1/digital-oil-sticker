# Factual-use and marks policy

Adopted by the owner 2026-08-01 (planning review rev 2). This document states the copyright, trademark, attribution, and no-affiliation rules for the Digital Oil Sticker catalog and UI. It is a planning/engineering policy, not a legal opinion; a lawyer reviews the final EOLCS acquisition method and the public recommendation copy before launch.

## Project statement

> Digital Oil Sticker stores independently structured factual observations. It does not reproduce source prose, images, logos, manuals, standards, or proprietary database presentation. Copyright fair use is a fallback for limited, source-attributed excerpts — not the primary legal basis for the factual catalog.

## Copyright posture

Facts are not copyrightable (U.S. Copyright Office FAQ; *Feist Publications v. Rural Telephone Service*, 499 U.S. 340). An original selection or arrangement of facts can carry thin compilation protection; our schema is independently designed and our selection criteria are our own (the INV-8/9 coverage contract), so these fields are stored as factual observations:

model year · make · model · trim/configuration name · engine displacement · cylinder count · fuel type · transmission · drivetrain · electrification type · oil viscosity grade · oil capacity · oil-filter part number · maintenance interval · oil brand and product-family names · API service category and other specification identifiers.

**Never copy:** source descriptions verbatim; manual prose; source-specific table layouts; photographs or product-label artwork; manufacturer or certification logos (including the API donut, starburst, and shield); a private directory's entire selection and arrangement; substantial portions of a copyrighted manual or standard.

### Source-level authorization (recorded separately per source)

- **NHTSA vPIC — approved.** Basis: NHTSA's express open-data authorization (vPIC FAQ: no license or registration required; free for public use) combined with the factual nature of the extracted fields. **Not** claimed as a blanket §105 federal work — vPIC content is populated partly from manufacturer submissions. Operational controls, not rights gates: ID-based endpoints only; rate control and `Retry-After`; cache and resume; provenance timestamps preserved; NHTSA/vPIC attribution; no implied endorsement; no VINs or user-entered data in telemetry; release-notes monitoring.
- **FuelEconomy.gov (DOE/EPA) — approved,** with its authorization evidence recorded separately from vPIC: documented bulk downloads offered for all model years; DOE web policy states government information on DOE sites is public domain with attribution requested, third-party-marked material excepted. Record per acquisition: dataset URL, retrieval date, file hash, documentation version, attribution, field-specific notices, crosswalk confidence, and the EPA-tested-light-duty coverage limitation.
- **API EOLCS — private-directory access and redistribution review required.** API is a private trade association; individual facts ("Product X holds API SP licensing as of [date]") are not copyrightable, but separate risks attach to the access terms under which the site is used, automated collection, copying the directory as a compilation, redistributing a directory substitute, certification-mark use, and implied authorization. `robots.txt` is preserved as dated evidence of access expectations — an automation instruction, not a copyright license. EOLCS contributes **zero production rows** until its acquisition and redistribution method is approved; it is reserved as a separately-reviewed certification-verification source.
- **Oil-manufacturer publications — approved for independent factual extraction.** Product pages, technical data sheets, and labels may be read to record factual fields in our own words and schema, with per-row provenance (`product_url` / `data_sheet_url`, `source_observed_at`, `source_type`, reviewer). No copied marketing prose, photography, label artwork, or logos.

## Trademark posture: referential use

Names such as Ford, Toyota, F-150, Mobil 1, Valvoline, and Castrol may be trademarks. Infringement turns principally on likely confusion about source, sponsorship, or affiliation (USPTO). The app's policy:

- Use names only to identify the vehicle or product the user is selecting.
- Render names in the app's normal typeface. No logos, no trade dress, no packaging reproduction.
- Use only as much of a mark as necessary; never place a manufacturer name in the app's own brand lockup.
- Do not use ® or ™ (no per-mark policy exists; omitting is the deliberate default).
- A build test asserts no third-party logo or certification-mark asset exists in the repository or any shipped artifact.

## No-affiliation statement (rendered on the attribution page, verbatim)

> Vehicle, lubricant, and filter names are used only to identify applicable vehicles and products. Digital Oil Sticker is independent and is not sponsored, approved, or endorsed by vehicle manufacturers, lubricant manufacturers, filter manufacturers, NHTSA, EPA, DOE, SAE International, or the American Petroleum Institute.

## Source dispositions (replaces the single `rights_disposition` gate)

Each `data_sources` row records six separate dimensions — different legal questions, never conflated:

| Field | Values |
| --- | --- |
| `copyright_basis` | `government_public_domain` · `factual_extraction` · `licensed` · `limited_fair_use` · `unknown` |
| `acquisition_basis` | `public_api` · `official_bulk_download` · `manufacturer_publication` · `direct_observation` · `licensed_feed` · `user_entry` · `prohibited` · `unknown` |
| `redistribution_basis` | `factual_republication` · `express_permission` · `license` · `internal_verification_only` · `prohibited` · `unknown` |
| `trademark_posture` | `plain_text_reference` · `authorized_mark` · `no_mark_used` · `review_required` |
| `claim_posture` | `identity_only` · `unverified_product_fact` · `manufacturer_claim` · `independently_verified` · `derived_match` · `prohibited` |
| `review_status` | `approved` · `approved_with_conditions` · `pending` · `rejected` |

**Withholding rule:** a row is withheld when its acquisition method, redistribution basis, or resulting product claim is unresolved — not merely because its source is private. Harmless identity fields from an approved source never require per-row legal review.

## Territory

Initial release territory: **United States.** Another review is required before targeted UK/EU distribution.
