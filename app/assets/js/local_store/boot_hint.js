// Non-personal boot hint (INV-23, INV-25): the ONLY localStorage key this app
// writes besides phx:theme. It records whether this origin has ever held data —
// never what it held — so an evicted/cleared store is distinguishable from a
// genuine first visit.

const KEY = "dos_boot_state"

/** @returns {"never" | "has_data"} */
export function readBootHint() {
  try {
    return localStorage.getItem(KEY) === "has_data" ? "has_data" : "never"
  } catch {
    // localStorage blocked: indistinguishable from a first visit by design.
    return "never"
  }
}

export function markHasData() {
  try {
    localStorage.setItem(KEY, "has_data")
  } catch {
    // Blocked storage: the hint is best-effort and never fatal.
  }
}

/** After a user-chosen erase: the store is empty ON PURPOSE, so the next boot
 * must read as a first visit, not as "your records are gone". */
export function markNever() {
  try {
    localStorage.setItem(KEY, "never")
  } catch {
    // Blocked storage: the hint is best-effort and never fatal.
  }
}
