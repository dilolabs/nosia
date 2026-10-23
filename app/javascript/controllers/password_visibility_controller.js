import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "input", "button" ]
  static values = { show: String, hide: String, showLabel: String, hideLabel: String }

  connect() {
    this.setVisibility(false)
  }

  toggle() {
    this.setVisibility(this.inputTarget.type === "password")
  }

  reset() {
    this.inputTarget.value = ""
    this.setVisibility(false)
  }

  setVisibility(visible) {
    this.inputTarget.type = visible ? "text" : "password"
    this.buttonTarget.textContent = visible ? this.hideValue : this.showValue
    this.buttonTarget.setAttribute("aria-label", visible ? this.hideLabelValue : this.showLabelValue)
    this.buttonTarget.setAttribute("aria-pressed", String(visible))
  }
}
