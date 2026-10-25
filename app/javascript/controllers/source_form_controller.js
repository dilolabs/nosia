import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["errors"]

  connect() {
    this.focusErrors = this.focusErrors.bind(this)
    this.focusField = this.focusField.bind(this)
    document.addEventListener("turbo:render", this.focusErrors)
    this.element.addEventListener("click", this.focusField)
    this.focusErrors()
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.focusErrors)
    this.element.removeEventListener("click", this.focusField)
  }

  focusErrors() {
    if (this.hasErrorsTarget) this.errorsTarget.focus()
  }

  focusField(event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const link = event.target.closest(".n-source-error-link")
    if (link && this.hasErrorsTarget && this.errorsTarget.contains(link)) {
      const href = link.getAttribute("href")
      const field = href?.startsWith("#") && document.getElementById(href.slice(1))

      if (field && this.element.contains(field)) {
        event.preventDefault()
        field.focus()
      }
    }
  }
}
