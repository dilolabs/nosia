import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.openers = new Map()
    this.caching = false
    this.recovery = null
  }

  open(event) {
    event.preventDefault()
    this.openDialog(document.getElementById(event.params.id), event.currentTarget)
  }

  openDialog(dialog, opener) {
    if (!dialog || !this.element.contains(dialog)) return

    this.recovery = null
    this.caching = false
    this.openers.set(dialog.id, { element: opener, id: opener?.id })
    this.element.querySelectorAll("dialog:modal").forEach(item => {
      if (item !== dialog) item.close()
    })
    if (!dialog.matches(":modal")) {
      if (dialog.open) dialog.close()
      const initialFocus = dialog.querySelector("[data-chat-dialog-initial-focus]")
      initialFocus?.setAttribute("autofocus", "")
      try {
        dialog.showModal()
      } finally {
        initialFocus?.removeAttribute("autofocus")
      }
    }
  }

  close(event) {
    event.preventDefault()
    this.closeDialog(event.target.closest("dialog"))
  }

  closeDialog(dialog, fallback = null) {
    if (!dialog) return

    this.recovery = null
    if (!this.openers.has(dialog.id) && fallback) this.openers.set(dialog.id, { element: fallback, id: fallback.id })
    dialog.close()
  }

  closed(event) {
    if (event.target.open) return

    const opener = this.openerFor(event.target.id)
    if (!this.caching && !this.element.querySelector("dialog:modal") && opener?.isConnected) opener.focus()
    this.openers.delete(event.target.id)
  }

  openerFor(id, entry = this.openers.get(id)) {
    let opener = entry?.element
    if (!opener?.isConnected && entry?.id) opener = document.getElementById(entry.id)
    if (!opener?.isConnected && entry) {
      const escaped = CSS.escape(id)
      opener = this.element.querySelector(`[data-chat-dialog-id-param="${escaped}"][aria-controls="${escaped}"]`)
    }
    return opener
  }

  reconfigure(dialog, configure, fallback) {
    this.recovery = null
    const active = document.activeElement, inside = dialog.contains(active)
    this.openers.delete(dialog.id)
    if (dialog.open) dialog.close()
    configure()
    if (active?.isConnected && active.checkVisibility()) {
      if (document.activeElement !== active) active.focus({ preventScroll: true })
    } else if (inside && fallback?.isConnected) fallback.focus({ preventScroll: true })
  }

  focus(element) {
    element?.focus()
  }

  beforeVisit(event) {
    this.recovery = null
    this.refreshURL = event.detail.url === location.href ? location.href : null
  }

  beforeCache() {
    // Only the shared panel moved out of the chat root. Tools keeps its existing
    // disclosure recovery; snapshots of both remain closed.
    const panel = this.element.querySelector("#chat-history:modal")
    const active = document.activeElement
    this.recovery = this.refreshURL && panel ? {
      url: this.refreshURL,
      context: this.element.querySelector(".n-chat-workspace")?.id,
      opener: this.openers.get(panel.id),
      focus: { element: active, id: active.id }
    } : null
    this.refreshURL = null
    this.caching = true
    this.openers.clear()
    this.element.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
  }

  beforeRender(event) {
    if (!this.recovery) return

    const shell = event.detail.newBody.querySelector(`#${CSS.escape(this.element.id)}`)
    if (!shell || (this.recovery.context && !shell.querySelector(`#${CSS.escape(this.recovery.context)}`))) this.recovery = null
  }

  afterRender() {
    this.caching = false
    const recovery = this.recovery
    this.recovery = null
    if (!recovery || recovery.url !== location.href || !this.element.isConnected) return

    const panel = this.element.querySelector("#chat-history")
    if (!panel || panel.dataset.inline === "true" || this.element.querySelector("dialog:modal")) return

    const opener = this.openerFor(panel.id, recovery.opener)
    const active = document.activeElement
    if (active !== document.body && active !== document.documentElement && active !== opener) return

    this.openDialog(panel, opener)
    const focus = recovery.focus.element.isConnected ? recovery.focus.element :
      recovery.focus.id && panel.querySelector(`#${CSS.escape(recovery.focus.id)}`)
    if (focus && panel.contains(focus) && focus.checkVisibility()) focus.focus({ preventScroll: true })
  }
}
