import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel"]

  open(event) {
    if (!this.panelTarget.showPopover) return

    if (this.popoverOpen) {
      this.dismiss(event)
    } else {
      event.preventDefault()
      this.panelTarget.showPopover({ source: this.triggerTarget })
    }
  }

  dismiss(event) {
    if (event.defaultPrevented || !this.popoverOpen) return

    event.preventDefault()
    event.stopPropagation()
    this.panelTarget.hidePopover()
    this.triggerTarget.focus({ preventScroll: true })
  }

  focusChanged(event) {
    // Focus has already landed outside the panel and its trigger. Leave it there.
    if (this.popoverOpen && !this.element.contains(event.target)) this.panelTarget.hidePopover()
  }

  preserveOpen(event) {
    if (event.target === this.panelTarget && event.detail.attributeName === "open" &&
        event.detail.mutationType === "remove" && this.panelTarget.matches(":modal")) event.preventDefault()
  }

  get popoverOpen() {
    return this.hasPanelTarget && this.panelTarget.matches(":popover-open")
  }
}
