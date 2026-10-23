import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "errors" ]

  connect() {
    this.focusErrors = this.focusErrors.bind(this)
    document.addEventListener("turbo:render", this.focusErrors)
    this.focusErrors()
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.focusErrors)
  }

  focusErrors() {
    if (this.hasErrorsTarget) this.errorsTarget.focus()
  }
}
