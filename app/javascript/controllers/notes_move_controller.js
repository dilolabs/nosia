import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

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
    // Focus has already landed outside the picker and its trigger. Leave it there.
    if (this.popoverOpen && !this.element.contains(event.target)) this.panelTarget.hidePopover()
  }

  preserveOpen(event) {
    if (event.target === this.panelTarget && event.detail.attributeName === "open" &&
        event.detail.mutationType === "remove" && this.panelTarget.matches(":modal")) event.preventDefault()
  }

  rememberDestination(event) {
    const select = event.currentTarget
    if (event.target !== select) return

    this.destinationBeforeMorph = this.pickerOpen && event.detail.newElement ? { select, value: select.value } : null
  }

  restoreDestination(event) {
    const select = event.currentTarget
    if (event.target !== select) return

    const previous = this.destinationBeforeMorph
    this.destinationBeforeMorph = null
    if (previous?.select !== select || !select.isConnected || !this.pickerOpen) return

    // Turbo skips the children of the focused select. Refresh them without moving focus.
    if (select === document.activeElement) Turbo.morphChildren(select, event.detail.newElement)
    const available = Array.from(select.options).some(option => option.value === previous.value && !option.matches(":disabled"))
    select.value = available ? previous.value : ""
  }

  get popoverOpen() {
    return this.hasPanelTarget && this.panelTarget.matches(":popover-open")
  }

  get pickerOpen() {
    return this.hasPanelTarget && this.panelTarget.matches(":popover-open, :modal")
  }
}
