// AnnounceCount: mirrors this element's data-count attribute into a polite live
// region, debounced so rapid updates announce once. A live region announces on
// its own — this hook never moves focus.

const DEBOUNCE_MS = 400

export const AnnounceCount = {
  mounted() {
    this.timer = null
    this.observer = new MutationObserver(() => this.schedule())
    this.observer.observe(this.el, {attributes: true, attributeFilter: ["data-count"]})
  },

  destroyed() {
    this.observer.disconnect()
    if (this.timer) clearTimeout(this.timer)
  },

  schedule() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.announce(), DEBOUNCE_MS)
  },

  announce() {
    this.timer = null
    const target = this.target()
    if (!target) return
    target.textContent = this.el.getAttribute("data-count") || ""
  },

  /** The live region: data-announce-target selector if given, else this element. */
  target() {
    const selector = this.el.getAttribute("data-announce-target")
    return selector ? document.querySelector(selector) : this.el
  },
}
