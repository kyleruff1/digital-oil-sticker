// The LocalStore phx-hook (DOS-M09-002): sole client-side owner of the
// hydration/mutation protocol. All IndexedDB work goes through the
// local_store/idb.js adapter; this hook holds no storage-layout knowledge.
// Nothing here logs record content, tab_id, or any personal value.

import {SCHEMA_VERSION} from "../local_store/schema.js"
import * as idb from "../local_store/idb.js"
import {readBootHint, markHasData, markNever} from "../local_store/boot_hint.js"
import {openBroadcast, broadcastAvailable} from "../local_store/broadcast.js"
import {buildEnvelope, emptyData} from "../local_store/envelope.js"
import {exportFile} from "../local_store/export.js"

export const LocalStore = {
  mounted() {
    // Ephemeral per-tab identifier: regenerated every tab load, never persisted
    // to any store or cookie, never logged, never exported (INV-3, INV-4).
    this.tabId = crypto.randomUUID()
    this.lastSeq = 0
    this.db = null
    this.persistRequested = false
    this.channel = openBroadcast(msg => this.onBroadcast(msg))

    this.handleEvent("local_store:put", payload => this.applyPut(payload))
    this.handleEvent("local_store:request_persist", () => this.requestPersist())
    this.handleEvent("local_store:export", () => this.exportData())
    // Conflict recovery: the server saw a write lose the seq compare-and-set
    // (another tab committed first) and needs the newer state. Before this
    // handler existed the event was pushed and silently dropped, leaving the
    // losing tab a skeleton until its broadcast handler happened to race in.
    this.handleEvent("local_store:rehydrate", () => this.hydrate())
    this.handleEvent("local_store:erase", () => this.eraseEverything())

    this.hydrate()
  },

  reconnected() {
    // Hydration is per-mount (INV-7): the server never assumes surviving
    // assigns, so every reconnect re-runs the full hydrate path.
    this.hydrate()
  },

  destroyed() {
    if (this.channel) this.channel.close()
    if (this.db) {
      this.db.close()
      this.db = null
    }
  },

  async hydrate() {
    if (!this.db) {
      const acquired = await this.acquireDatabase()
      if (!acquired.ok) {
        this.pushSessionOnly(acquired.error.kind)
        return
      }
      // Racing left the open pending: an envelope was already pushed for the
      // timeout, and a late success re-enters hydrate() with this.db set.
      if (acquired.pending) return
      this.db = acquired.db
    }

    const read = await idb.readAll(this.db)
    if (!read.ok) {
      this.pushSessionOnly(read.error.kind)
      return
    }
    const estimate = await idb.estimateQuota()
    const meta = read.data.meta
    this.lastSeq = meta && typeof meta.seq === "number" ? meta.seq : 0

    const envelope = buildEnvelope({
      schemaVersion: (meta && meta.schema_version) || SCHEMA_VERSION,
      seq: this.lastSeq,
      tabId: this.tabId,
      nowIso: new Date().toISOString(),
      data: read.data,
      storage: {
        mode: "idb",
        boot_hint: readBootHint(),
        persist_granted: meta && meta.persist_granted !== undefined ? meta.persist_granted : null,
        estimate,
        broadcast_channel: broadcastAvailable(),
      },
    })
    this.pushEvent("local_store:hydrate", envelope)
  },

  /** Open the database and prove writability, bounded by a timeout.
   *
   * An IndexedDB open can hang without ever settling (a wedged backing store —
   * seen on Chromium-family profiles on Windows). Un-raced, hydrate() then
   * never pushes an envelope, the server's 5s deadline lapses into
   * :storage_unavailable with storage_mode still :unknown, and NO banner
   * renders — the page looks healthy while every save is refused. The 3s
   * bound beats that deadline, so a hung open reports an honest session_only
   * envelope and the banner the state deserves. If the open settles later,
   * the real hydrate runs and the session upgrades itself. */
  acquireDatabase() {
    const openAndProbe = (async () => {
      const opened = await idb.openDatabase()
      if (!opened.ok) return opened
      // A database can open and still reject writes (private browsing, blocked
      // storage), so writability is proven before any envelope claims a mode.
      const probe = await idb.probeRoundTrip(opened.db)
      if (!probe.ok) {
        opened.db.close()
        return probe
      }
      return {ok: true, db: opened.db}
    })()

    let timer
    const timeout = new Promise(resolve => {
      timer = setTimeout(() => resolve({ok: false, timedOut: true}), 3000)
    })

    return Promise.race([openAndProbe, timeout]).then(winner => {
      clearTimeout(timer)
      if (!winner.timedOut) return winner

      this.pushSessionOnly("open_timeout")
      openAndProbe.then(result => {
        // The hook may have been destroyed while the open dangled.
        if (result.ok && this.el && this.el.isConnected && !this.db) {
          this.db = result.db
          this.hydrate()
        } else if (result.ok && result.db !== this.db) {
          result.db.close()
        }
      })
      return {ok: true, pending: true}
    })
  },

  /** Storage could not be opened or is not writable: hydrate with empty data
   * and an explicit session_only mode so the server can render the honest
   * storage-unavailable state instead of a cheerful empty garage (INV-24.6). */
  pushSessionOnly(reason) {
    const envelope = buildEnvelope({
      schemaVersion: SCHEMA_VERSION,
      seq: 0,
      tabId: this.tabId,
      nowIso: new Date().toISOString(),
      data: emptyData(),
      storage: {
        mode: "session_only",
        reason,
        boot_hint: readBootHint(),
        persist_granted: null,
        estimate: null,
        broadcast_channel: broadcastAvailable(),
      },
    })
    this.pushEvent("local_store:hydrate", envelope)
  },

  async applyPut(payload) {
    if (!this.db) {
      this.pushEvent("local_store:ack", {
        mutation_id: payload.mutation_id,
        seq: payload.seq,
        status: "error",
        reason: "unavailable",
      })
      return
    }

    const result = await idb.applyPut(this.db, payload, new Date().toISOString())

    if (result.ok) {
      this.lastSeq = payload.seq
      markHasData()
      this.channel.post({seq: payload.seq, mutation_id: payload.mutation_id, tab_id: this.tabId})
      this.pushEvent("local_store:ack", {
        mutation_id: payload.mutation_id,
        seq: payload.seq,
        status: "ok",
      })
    } else if (result.error.kind === "conflict") {
      this.pushEvent("local_store:conflict", {
        expected_seq: result.error.expected_seq,
        found_seq: result.error.found_seq,
        mutation_id: payload.mutation_id,
      })
    } else {
      this.pushEvent("local_store:ack", {
        mutation_id: payload.mutation_id,
        seq: payload.seq,
        status: "error",
        reason: result.error.kind,
      })
    }
  },

  onBroadcast(msg) {
    if (!msg || msg.tab_id === this.tabId) return
    if (typeof msg.seq === "number" && msg.seq > this.lastSeq) {
      this.hydrate()
    }
  },

  async requestPersist() {
    if (this.persistRequested) return
    this.persistRequested = true
    const result = await idb.requestPersistence()
    this.pushEvent("local_store:persist_result", {result})
  },

  async exportData() {
    if (!this.db) return
    const read = await idb.readAll(this.db)
    if (!read.ok) return
    const nowIso = new Date().toISOString()
    const meta = read.data.meta
    const envelope = buildEnvelope({
      schemaVersion: (meta && meta.schema_version) || SCHEMA_VERSION,
      seq: meta && typeof meta.seq === "number" ? meta.seq : 0,
      tabId: this.tabId,
      nowIso,
      data: read.data,
      storage: null,
    })
    await exportFile(envelope, nowIso)
  },

  /** User-confirmed erase of everything this origin stores. The confirmation
   * happened in the LiveView modal before this event was pushed; by the time
   * we are here the only job is to do it completely and reboot honestly. */
  async eraseEverything() {
    if (this.db) {
      await idb.eraseAll(this.db)
    }

    // "never", not "has_data": the store is empty ON PURPOSE. Leaving the
    // hint latched would make the next boot read as "your records are gone".
    markNever()

    // Full reload: every view re-mounts against the empty store and renders
    // the first-visit state. Other tabs recover through the seq-conflict →
    // rehydrate path on their next write.
    window.location.reload()
  },
}
