// DateSelect: client-side mirror of the server's day clamping, purely to avoid
// a round-trip flash of an invalid day. The server's value always wins — this
// hook only clears an obviously-invalid day back to its prompt; it never picks
// a replacement value.

export const DateSelect = {
  mounted() {
    this.onChange = event => {
      const target = event.target
      if (target === this.select("month") || target === this.select("year")) {
        this.clampDay()
      }
    }
    this.el.addEventListener("change", this.onChange)
  },

  destroyed() {
    this.el.removeEventListener("change", this.onChange)
  },

  clampDay() {
    const daySelect = this.select("day")
    const monthSelect = this.select("month")
    if (!daySelect || !monthSelect) return
    if (daySelect.value === "" || monthSelect.value === "") return

    const month = parseInt(monthSelect.value, 10)
    const day = parseInt(daySelect.value, 10)
    if (Number.isNaN(month) || Number.isNaN(day)) return

    const yearSelect = this.select("year")
    const yearValue = yearSelect && yearSelect.value !== "" ? parseInt(yearSelect.value, 10) : null
    // With no year chosen, use a leap year so February keeps 29 available; the
    // server clamps for real once the year is known.
    const year = yearValue === null || Number.isNaN(yearValue) ? 2000 : yearValue

    const daysInMonth = new Date(year, month, 0).getDate()
    if (day > daysInMonth) {
      daySelect.value = ""
    }
  },

  select(role) {
    return (
      this.el.querySelector(`select[data-date-role="${role}"]`) ||
      this.el.querySelector(`select[name*="${role}"]`)
    )
  },
}
