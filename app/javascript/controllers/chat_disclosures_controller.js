import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.states = this.element.chatDetailStates ||= new Map()
    this.streamRenders = new Set()
    this.observer = new MutationObserver(() => this.restore())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.restore()
  }

  disconnect() {
    this.observer.disconnect()
    this.pendingFocus = null
    this.pendingDialog = null
    for (const cancel of this.streamRenders) cancel()
  }

  beforeVisit(event) {
    this.refreshing = event.detail.url === location.href
    this.pendingDialog = null
  }

  beforeCache() {
    const dialog = this.element.querySelector("dialog.n-chat-dialog[open]")
    if (this.refreshing && dialog) this.pendingDialog = { id: dialog.id, focus: document.activeElement }
  }

  remember(event) {
    if (event.target.matches("details[data-chat-detail][id]")) {
      this.states.set(event.target.id, event.target.open)
    }
  }

  preserveAttribute(event) {
    const target = event.target
    if (event.detail.attributeName !== "open" || !this.element.contains(target)) return
    if ((target.matches("details[data-chat-detail][id]") && this.states.has(target.id)) ||
        target.matches("dialog.n-chat-dialog[open]")) event.preventDefault()
  }

  captureFocus(event) {
    let target = this.element
    if (event.type === "turbo:before-stream-render") {
      const id = event.target.getAttribute("target")
      target = id && this.element.querySelector(`#${CSS.escape(id)}`)
    } else if (!event.detail.newBody.querySelector(`#${CSS.escape(this.element.id)}`)) {
      this.pendingFocus = null
      this.pendingDialog = null
      return
    }

    const active = document.activeElement
    const detail = active?.closest("details[data-chat-detail][id]")
    if (target?.contains(active) && detail && this.element.contains(detail)) {
      const pending = { element: active, id: active.id, summaryId: detail.querySelector("summary[id]")?.id }
      if (event.type === "turbo:before-stream-render") {
        this.renderWithFocus(event, pending)
      } else {
        this.pendingFocus = pending
      }
    }
  }

  renderWithFocus(event, pending) {
    const render = event.detail.render
    let active = true, latestFocus = pending.element
    // Observe ordinary focus moves, including returns; do not classify Turbo's own focus.
    const focused = event => {
      if (!this.restoringFocus) latestFocus = event.target
    }
    const cancel = () => {
      active = false
      document.removeEventListener("focusin", focused, true)
      this.streamRenders.delete(cancel)
    }
    this.streamRenders.add(cancel)
    document.addEventListener("focusin", focused, true)
    queueMicrotask(() => { if (event.defaultPrevented) cancel() })
    event.detail.render = async stream => {
      try {
        const result = await render(stream)
        if (active && this.element.isConnected) {
          this.restore()
          if (latestFocus === pending.element || (pending.id && latestFocus.id === pending.id)) this.restoreFocus(pending)
        }
        return result
      } finally {
        cancel()
      }
    }
  }

  restore(event) {
    this.element.querySelectorAll("details[data-chat-detail][id]").forEach(detail => {
      if (this.states.has(detail.id)) {
        if (detail.open !== this.states.get(detail.id)) detail.open = this.states.get(detail.id)
      } else {
        this.states.set(detail.id, detail.open)
      }
    })

    if (event?.type === "turbo:render" && this.pendingDialog) {
      const { id, focus } = this.pendingDialog
      this.pendingDialog = null
      // Cache snapshots stay closed. Ask the dialog owner to reopen only this refresh.
      const opener = this.element.querySelector(`[data-chat-dialog-id-param="${CSS.escape(id)}"][aria-controls="${CSS.escape(id)}"]`)
      if (this.refreshing && !this.element.querySelector("dialog[open]") &&
          (document.activeElement === document.body || document.activeElement === opener)) {
        opener?.click()
        if (focus.isConnected && focus.closest("dialog")?.open) focus.focus({ preventScroll: true })
      }
      this.refreshing = false
    }

    const pending = this.pendingFocus
    this.pendingFocus = null
    if (pending) this.restoreFocus(pending)
  }

  restoreFocus(pending) {
    if (!pending || (document.activeElement !== document.body && document.activeElement !== document.documentElement)) return
    const find = id => id && this.element.querySelector(`#${CSS.escape(id)}`)
    const target = find(pending.id) || find(pending.summaryId)
    const dialog = target?.closest("dialog")
    const modal = this.element.querySelector("dialog[open]")
    if (target && (!dialog || dialog.open) && (!modal || modal.contains(target))) {
      this.restoringFocus = true
      try {
        target.focus({ preventScroll: true })
      } finally {
        this.restoringFocus = false
      }
    }
  }
}
