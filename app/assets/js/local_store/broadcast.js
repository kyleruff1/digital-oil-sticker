// Cross-tab write signaling (INV-24.7). Messages carry ONLY
// {seq, mutation_id, tab_id} — never record content.

const CHANNEL_NAME = "dos_local_store"

export function broadcastAvailable() {
  return typeof BroadcastChannel !== "undefined"
}

/** Open the cross-tab channel. Where BroadcastChannel is unavailable, returns a
 * no-op object so callers degrade to per-mount hydration only; the meta.seq
 * compare-and-set still prevents lost updates. */
export function openBroadcast(onMessage) {
  if (!broadcastAvailable()) {
    return {
      post() {},
      close() {},
    }
  }

  const channel = new BroadcastChannel(CHANNEL_NAME)
  channel.onmessage = event => {
    const msg = event && event.data
    if (msg && typeof msg === "object") {
      onMessage({seq: msg.seq, mutation_id: msg.mutation_id, tab_id: msg.tab_id})
    }
  }

  return {
    post({seq, mutation_id, tab_id}) {
      try {
        channel.postMessage({seq, mutation_id, tab_id})
      } catch {
        // A closed channel must never break the commit path.
      }
    },
    close() {
      try {
        channel.close()
      } catch {
        // already closed
      }
    },
  }
}
