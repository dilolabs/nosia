import { Controller } from "@hotwired/stimulus"

const POLL_MS = 5000

export default class extends Controller {
  static targets = ["message", "outcome", "actions"]

  connect() {
    this.pane = this.element.closest(".n-notes-reader")
    if (!this.pane) return

    this.visibility = new ResizeObserver(() => this.schedule())
    this.visibility.observe(this.pane)
    this.schedule()
  }

  disconnect() {
    this.visibility?.disconnect()
    this.stop()
  }

  schedule() {
    if (!this.#canPoll) {
      this.stop()
    } else if (!this.timer && !this.poll) {
      this.timer = setTimeout(() => this.#refresh(), POLL_MS)
    }
  }

  stop() {
    clearTimeout(this.timer)
    this.timer = null
    this.#cancelPoll()
  }

  saved({ detail: html }) {
    const frame = this.#frameFrom(html)
    if (!frame || !this.#apply(frame)) return

    this.#cancelPoll()
    this.schedule()
  }

  rememberFocus({ submitter }) {
    this.retryButton = submitter
    this.restoreFocus = document.activeElement === this.retryButton
    this.outcomeTarget.textContent = ""
  }

  finishRetry() {
    if (this.retryFailed) this.#restoreRetryFocus()
  }

  checkRetry(event) {
    const { succeeded, location } = event.detail.fetchResponse
    const retryStatus = new URL(location)
    if (/^\d+$/.test(retryStatus.searchParams.get("retry_failed"))) retryStatus.searchParams.delete("retry_failed")
    if (!succeeded || retryStatus.href !== new URL(this.element.dataset.statusUrl, window.location.origin).href) {
      event.preventDefault()
      this.retryError()
    }
  }

  retryError() {
    if (this.messageTarget.dataset.noteIndexStatus === "failed") this.messageTarget.textContent = this.element.dataset.retryError
    // Turbo re-enables the submitter just before submit-end.
    if (this.retryButton?.disabled) this.retryFailed = true
    else this.#restoreRetryFocus()
  }

  renderRetry(event) {
    event.detail.render = (_current, frame) => {
      if (this.#apply(frame)) this.schedule()
      this.#restoreRetryFocus()
    }
  }

  get #visible() {
    return this.element.isConnected && !document.hidden && Boolean(this.pane?.getClientRects().length)
  }

  get #canPoll() {
    return this.#visible && this.element.dataset.statusUrl && this.messageTarget.dataset.noteIndexStatus === "pending"
  }

  #cancelPoll() {
    this.poll?.abort()
    this.poll = null
  }

  async #refresh() {
    this.timer = null
    if (!this.#canPoll) return

    const poll = this.poll = new AbortController()
    try {
      const response = await fetch(this.element.dataset.statusUrl, {
        cache: "no-store", redirect: "error", signal: poll.signal,
        headers: { Accept: "text/html", "Turbo-Frame": this.element.id }
      })
      if (!response.ok) throw new Error("Status request failed")

      const frame = this.#frameFrom(await response.text())
      if (!frame) throw new Error("Status frame missing")
      if (this.poll !== poll || !this.#visible) return

      this.#apply(frame)
      this.poll = null
      this.schedule()
    } catch {
      if (this.poll === poll && this.#visible) {
        this.messageTarget.dataset.noteIndexStatus = "unavailable"
        this.messageTarget.textContent = this.element.dataset.pollError
      }
    } finally {
      if (this.poll === poll) this.poll = null
    }
  }

  #frameFrom(html) {
    const template = document.createElement("template")
    template.innerHTML = html || ""
    return template.content.querySelector("turbo-frame#note-index-status")
  }

  #apply(frame) {
    const { statusUrl, revision, generation, updatedAt } = frame.dataset
    const current = this.element.dataset
    // A poll or retry may have started before a newer save was acknowledged.
    // On the same revision, indexing itself can have updated the saved state.
    if (!statusUrl || (current.statusUrl && current.statusUrl !== statusUrl) ||
        BigInt(revision) < BigInt(current.revision) ||
        BigInt(generation) < BigInt(current.generation) ||
        (revision === current.revision && generation === current.generation && updatedAt < current.updatedAt)) return false

    const message = frame.querySelector("[data-note-index-status]")
    const state = message.dataset.noteIndexStatus
    const focused = this.actionsTarget.contains(document.activeElement)
    Object.assign(current, { statusUrl, revision, generation, updatedAt })
    this.messageTarget.dataset.noteIndexStatus = state
    if (this.messageTarget.textContent !== message.textContent) this.messageTarget.textContent = message.textContent
    const outcome = frame.querySelector('[data-note-index-status-target="outcome"]').textContent
    if (this.outcomeTarget.textContent !== outcome) this.outcomeTarget.textContent = outcome
    if (Boolean(this.actionsTarget.firstElementChild) !== (state === "failed")) {
      this.actionsTarget.replaceChildren(...frame.querySelector('[data-note-index-status-target="actions"]').children)
      if (focused) this.messageTarget.focus({ preventScroll: true })
    }
    return true
  }

  #restoreRetryFocus() {
    if (this.restoreFocus && [document.body, this.retryButton].includes(document.activeElement)) {
      const target = this.actionsTarget.querySelector("button") || this.messageTarget
      target.focus({ preventScroll: true })
    }
    this.restoreFocus = false
    this.retryFailed = false
    this.retryButton = null
  }
}
