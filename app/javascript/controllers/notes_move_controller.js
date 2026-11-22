import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  open(event) {
    if (event.currentTarget.commandForElement || !this.panelTarget.showModal) return

    event.preventDefault()
    event.currentTarget.focus({ preventScroll: true })
    this.panelTarget.showModal()
    this.dispatch("opened", { target: this.panelTarget })
  }

  close(event) {
    if (event.currentTarget.commandForElement || !this.panelTarget.open) return

    event.preventDefault()
    this.panelTarget.close()
  }

  preserveOpen(event) {
    if (event.target === this.panelTarget && event.detail.attributeName === "open" &&
        event.detail.mutationType === "remove" && this.panelTarget.matches(":modal")) event.preventDefault()
  }
}
