-- Digital Oil Sticker catalog schema (DOS-M04-002 baseline + rev-2 factual-use
-- dispositions). STRICT tables, stable text IDs (UUIDv5), unknown is NULL —
-- never '', 0, or false. Opened read-only at runtime (PRAGMA query_only = ON).

CREATE TABLE catalog_metadata (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE data_sources (
  id                   TEXT PRIMARY KEY,
  source_key           TEXT NOT NULL,
  provider             TEXT NOT NULL,
  source_type          TEXT NOT NULL,
  dataset_name         TEXT NOT NULL,
  canonical_url        TEXT NOT NULL,
  source_version       TEXT,
  raw_sha256           TEXT,
  retrieved_at         TEXT,
  effective_at         TEXT,
  verified_at          TEXT,
  attribution_text     TEXT NOT NULL,
  web_attribution_text TEXT,
  -- Rev-2 factual-use dispositions: six separate legal questions, never conflated.
  copyright_basis      TEXT NOT NULL CHECK (copyright_basis IN
    ('government_public_domain','factual_extraction','licensed','limited_fair_use','unknown')),
  acquisition_basis    TEXT NOT NULL CHECK (acquisition_basis IN
    ('public_api','official_bulk_download','manufacturer_publication','direct_observation',
     'licensed_feed','user_entry','prohibited','unknown')),
  redistribution_basis TEXT NOT NULL CHECK (redistribution_basis IN
    ('factual_republication','express_permission','license','internal_verification_only',
     'prohibited','unknown')),
  trademark_posture    TEXT NOT NULL CHECK (trademark_posture IN
    ('plain_text_reference','authorized_mark','no_mark_used','review_required')),
  claim_posture        TEXT NOT NULL CHECK (claim_posture IN
    ('identity_only','unverified_product_fact','manufacturer_claim','independently_verified',
     'derived_match','prohibited')),
  review_status        TEXT NOT NULL CHECK (review_status IN
    ('approved','approved_with_conditions','pending','rejected')),
  terms_sha256         TEXT,
  evidence_ref         TEXT,
  reviewed_at          TEXT,
  reviewer             TEXT,
  UNIQUE (source_key, source_version)
) STRICT;

CREATE TABLE makes (
  id                TEXT PRIMARY KEY,
  vpic_make_id      INTEGER UNIQUE,
  display_name      TEXT NOT NULL,
  normalized_name   TEXT NOT NULL UNIQUE,
  support_status    TEXT NOT NULL CHECK (support_status IN
    ('identity_only','schedule_supported','full_product_supported','not_applicable','unsupported')),
  first_window_year INTEGER,
  last_window_year  INTEGER,
  window_year_count INTEGER,
  source_id         TEXT NOT NULL REFERENCES data_sources(id)
) STRICT;
CREATE INDEX makes_normalized_name_idx ON makes (normalized_name);

CREATE TABLE models (
  id              TEXT PRIMARY KEY,
  make_id         TEXT NOT NULL REFERENCES makes(id),
  vpic_model_id   INTEGER,
  display_name    TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  source_id       TEXT NOT NULL REFERENCES data_sources(id),
  UNIQUE (make_id, normalized_name),
  UNIQUE (make_id, vpic_model_id)
) STRICT;
CREATE INDEX models_make_normalized_idx ON models (make_id, normalized_name);

CREATE TABLE vehicle_configurations (
  configuration_key      TEXT PRIMARY KEY,
  model_year             INTEGER NOT NULL CHECK (model_year BETWEEN 1900 AND 2100),
  make_id                TEXT NOT NULL REFERENCES makes(id),
  model_id               TEXT NOT NULL REFERENCES models(id),
  vpic_vehicle_type_id   INTEGER,
  vehicle_type_name      TEXT,
  trim                   TEXT,
  series                 TEXT,
  body_class             TEXT,
  drive_type             TEXT,
  fuel_primary           TEXT,
  fuel_secondary         TEXT,
  electrification_level  TEXT,
  engine_cylinders       INTEGER,
  displacement_l         REAL,
  engine_descriptor      TEXT,
  transmission           TEXT,
  transmission_descriptor TEXT,
  epa_size_class         TEXT,
  start_stop             TEXT,
  provider_namespace     TEXT,
  provider_key           TEXT,
  completeness_code      TEXT NOT NULL CHECK (completeness_code IN
    ('identity_only','configuration_enriched','configuration_verified')),
  support_status         TEXT NOT NULL CHECK (support_status IN
    ('identity_only','schedule_supported','full_product_supported','not_applicable','unsupported')),
  engine_oil_service     TEXT CHECK (engine_oil_service IN ('applicable','not_applicable')),
  crosswalk_status       TEXT CHECK (crosswalk_status IN
    ('exact','qualified','ambiguous','rejected','manual_review')),
  search_text            TEXT NOT NULL,
  source_id              TEXT NOT NULL REFERENCES data_sources(id)
) STRICT;
CREATE INDEX vehicle_configurations_ymm_idx
  ON vehicle_configurations (model_year, make_id, model_id, configuration_key);
CREATE UNIQUE INDEX vehicle_configurations_provider_idx
  ON vehicle_configurations (provider_namespace, provider_key)
  WHERE provider_key IS NOT NULL;

CREATE TABLE aliases (
  id               TEXT PRIMARY KEY,
  entity_type      TEXT NOT NULL CHECK (entity_type IN ('make','model','oil_brand')),
  entity_id        TEXT NOT NULL,
  normalized_alias TEXT NOT NULL,
  display_alias    TEXT NOT NULL,
  alias_kind       TEXT NOT NULL CHECK (alias_kind IN
    ('rename','badge','marketing','spelling','crosswalk')),
  source_id        TEXT NOT NULL REFERENCES data_sources(id),
  UNIQUE (entity_type, normalized_alias)
) STRICT;
CREATE INDEX aliases_lookup_idx ON aliases (entity_type, normalized_alias);

-- Independent oil product list (manufacturer publications; factual fields only;
-- EOLCS contributes zero rows pending its separately-reviewed acquisition basis).
CREATE TABLE oil_brands (
  id               TEXT PRIMARY KEY,
  display_name     TEXT NOT NULL,
  normalized_name  TEXT NOT NULL UNIQUE,
  market           TEXT NOT NULL DEFAULT 'US',
  source_id        TEXT NOT NULL REFERENCES data_sources(id),
  source_observed_at TEXT
) STRICT;

CREATE TABLE oil_products (
  id                  TEXT PRIMARY KEY,
  brand_id            TEXT NOT NULL REFERENCES oil_brands(id),
  product_family      TEXT NOT NULL,
  product_variant     TEXT,
  display_name        TEXT NOT NULL,
  normalized_name     TEXT NOT NULL,
  product_url         TEXT,
  data_sheet_url      TEXT,
  source_observed_at  TEXT,
  source_type         TEXT,
  verification_status TEXT NOT NULL CHECK (verification_status IN
    ('unverified','manufacturer_published','independently_verified')),
  source_id           TEXT NOT NULL REFERENCES data_sources(id),
  UNIQUE (brand_id, normalized_name)
) STRICT;

CREATE TABLE oil_product_claims (
  id           TEXT PRIMARY KEY,
  product_id   TEXT NOT NULL REFERENCES oil_products(id),
  claim_type   TEXT NOT NULL CHECK (claim_type IN
    ('sae_viscosity_grade','api_service_category','ilsac_specification','oem_specification')),
  claim_code   TEXT NOT NULL,
  claim_source TEXT NOT NULL,
  observed_at  TEXT NOT NULL,
  verification_status TEXT NOT NULL CHECK (verification_status IN
    ('unverified','manufacturer_published','independently_verified')),
  source_id    TEXT NOT NULL REFERENCES data_sources(id),
  UNIQUE (product_id, claim_type, claim_code)
) STRICT;

-- Created with full DDL and ZERO rows in build 1: no licensed schedule /
-- requirement / filter source exists yet. Their absence is the honest
-- identity_only state (feature flags in catalog_metadata), and M03 tickets
-- add rows later without a schema version bump.
CREATE TABLE maintenance_schedules (
  id                 TEXT PRIMARY KEY,
  configuration_key  TEXT NOT NULL REFERENCES vehicle_configurations(configuration_key),
  service_type       TEXT NOT NULL CHECK (service_type = 'engine_oil'),
  condition          TEXT NOT NULL CHECK (condition IN ('normal','severe','flexible')),
  interval_miles     INTEGER,
  interval_months    INTEGER,
  oil_life_monitor   INTEGER NOT NULL DEFAULT 0 CHECK (oil_life_monitor IN (0, 1)),
  recommendation_text TEXT,
  source_locator     TEXT NOT NULL,
  source_page        TEXT,
  source_effective_date TEXT,
  verification_state TEXT NOT NULL,
  source_id          TEXT NOT NULL REFERENCES data_sources(id),
  CHECK (interval_miles IS NOT NULL OR interval_months IS NOT NULL OR oil_life_monitor = 1)
) STRICT;
CREATE INDEX maintenance_schedules_config_idx ON maintenance_schedules (configuration_key);

CREATE TABLE oil_requirements (
  id                    TEXT PRIMARY KEY,
  configuration_key     TEXT NOT NULL REFERENCES vehicle_configurations(configuration_key),
  required_viscosity    TEXT,
  acceptable_viscosities TEXT,
  api_service_category  TEXT,
  oem_specification     TEXT,
  capacity_value        REAL,
  capacity_unit         TEXT,
  capacity_with_filter  INTEGER CHECK (capacity_with_filter IN (0, 1)),
  applicability_conditions TEXT,
  source_locator        TEXT NOT NULL,
  source_page           TEXT,
  source_effective_date TEXT,
  source_id             TEXT NOT NULL REFERENCES data_sources(id)
) STRICT;
CREATE INDEX oil_requirements_config_idx ON oil_requirements (configuration_key);

CREATE TABLE filter_brands (
  id              TEXT PRIMARY KEY,
  display_name    TEXT NOT NULL,
  normalized_name TEXT NOT NULL UNIQUE,
  source_id       TEXT NOT NULL REFERENCES data_sources(id)
) STRICT;

CREATE TABLE filter_products (
  id          TEXT PRIMARY KEY,
  brand_id    TEXT NOT NULL REFERENCES filter_brands(id),
  part_number TEXT NOT NULL,
  source_id   TEXT NOT NULL REFERENCES data_sources(id),
  UNIQUE (brand_id, part_number)
) STRICT;

CREATE TABLE filter_fitments (
  id                TEXT PRIMARY KEY,
  filter_product_id TEXT NOT NULL REFERENCES filter_products(id),
  configuration_key TEXT NOT NULL REFERENCES vehicle_configurations(configuration_key),
  position          TEXT,
  qualifiers        TEXT,
  source_id         TEXT NOT NULL REFERENCES data_sources(id),
  UNIQUE (filter_product_id, configuration_key)
) STRICT;
CREATE INDEX filter_fitments_config_idx ON filter_fitments (configuration_key);
