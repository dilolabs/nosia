import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  dismiss(event) {
    if (event.defaultPrevented || !this.element.matches(":popover-open")) return

    event.preventDefault()
    event.stopPropagation()
    this.element.hidePopover()
    this.element.previousElementSibling.focus({ preventScroll: true })
  }
}
