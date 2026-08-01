// Client-side mirror of the DOS-M09-001 storage schema. Structural layout only:
// record shapes, caps, and integrity rules are owned by the server-side validation.

export const DB_NAME = "dos_local"

// Structural IndexedDB version: bumped only when a store or index is added or
// changed. Distinct from SCHEMA_VERSION, the server-owned logical version.
export const IDB_VERSION = 1
export const SCHEMA_VERSION = 1

export const META_KEY = "meta"
export const PREFS_KEY = "prefs"

// `keyPath: null` marks an out-of-line singleton store keyed by `singletonKey`.
export const STORES = {
  meta: {keyPath: null, singletonKey: META_KEY, indexes: []},
  vehicles: {
    keyPath: "vehicle_id",
    indexes: [{name: "by_archived", keyPath: "archived"}],
  },
  events: {
    keyPath: "event_id",
    indexes: [
      {name: "by_vehicle", keyPath: "vehicle_id"},
      {name: "by_vehicle_performed", keyPath: ["vehicle_id", "performed_at"]},
    ],
  },
  readings: {
    keyPath: "reading_id",
    indexes: [
      {name: "by_vehicle", keyPath: "vehicle_id"},
      {name: "by_vehicle_observed", keyPath: ["vehicle_id", "observed_at"]},
    ],
  },
  usage: {
    keyPath: "usage_id",
    indexes: [
      {name: "by_vehicle", keyPath: "vehicle_id"},
      {name: "by_vehicle_effective", keyPath: ["vehicle_id", "effective_from"]},
    ],
  },
  reminders: {
    keyPath: "reminder_id",
    indexes: [{name: "by_vehicle", keyPath: "vehicle_id"}],
  },
  prefs: {keyPath: null, singletonKey: PREFS_KEY, indexes: []},
}

export const STORE_NAMES = Object.keys(STORES)
