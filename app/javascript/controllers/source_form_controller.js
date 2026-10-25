import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["errors"]

  connect() {
    if (this.hasErrorsTarget) this.errorsTarget.focus()
  }
}
