import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.openers = new Map()
    this.caching = false
  }

  open(event) {
    event.preventDefault()
    const dialog = document.getElementById(event.params.id)
    if (!dialog || !this.element.contains(dialog)) return

    this.caching = false
    this.openers.set(dialog.id, event.currentTarget)
    this.element.querySelectorAll("dialog[open]").forEach(item => item.close())
    dialog.showModal()
  }

  close(event) {
    event.preventDefault()
    event.target.closest("dialog")?.close()
  }

  closed(event) {
    let opener = this.openers.get(event.target.id)
    if (!opener?.isConnected) {
      const id = CSS.escape(event.target.id)
      opener = this.element.querySelector(`[data-chat-dialog-id-param="${id}"][aria-controls="${id}"]`)
    }
    if (!this.caching && !this.element.querySelector("dialog[open]") && opener?.isConnected) opener.focus()
    this.openers.delete(event.target.id)
  }

  beforeCache() {
    this.caching = true
    this.element.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
    this.openers.clear()
  }
}
