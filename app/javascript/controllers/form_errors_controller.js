import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summary"]

  summaryTargetConnected(summary) {
    summary.focus()
  }

  focusSummary() {
    if (this.hasSummaryTarget) this.summaryTarget.focus()
  }

  revealInvalid(event) {
    for (let disclosure = event.target.closest("details"); disclosure; disclosure = disclosure.parentElement?.closest("details")) disclosure.open = true
  }

  focusField(event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const link = event.target.closest("a[data-error-field]")
    if (!link || !this.hasSummaryTarget || !this.summaryTarget.contains(link)) return
    const field = document.getElementById(link.dataset.errorField)
    if (field && this.element.contains(field)) {
      event.preventDefault()
      this.revealInvalid({ target: field })
      field.focus()
    }
  }
}
