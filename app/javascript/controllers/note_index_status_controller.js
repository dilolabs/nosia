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
    this.suspend()
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

  suspend() {
    this.stop()
    if (this.retry) {
      this.retry.controller.abort()
      this.#finishRetry()
    }
  }

  saved({ detail: html }) {
    const frame = this.#frameFrom(html)
    if (!frame || !this.#apply(frame, { fromSave: true })) return

    this.#cancelPoll()
    this.schedule()
  }

  async submitRetry(event) {
    event.preventDefault()
    if (this.retry) return

    const form = event.target
    const body = new FormData(form)
    const generation = body.get("expected_generation")
    if (generation !== this.element.dataset.generation || !this.element.dataset.statusUrl) return

    const retry = this.retry = { controller: new AbortController(), button: event.submitter }
    this.outcomeTarget.textContent = ""
    this.element.setAttribute("aria-busy", "true")
    retry.button?.setAttribute("aria-disabled", "true")

    const result = await this.#requestRetry(form.action, body, retry.controller.signal)
    if (this.retry !== retry || !this.element.isConnected) return

    this.#finishRetry()
    if (generation !== this.element.dataset.generation) return

    if (!result) {
      this.outcomeTarget.textContent = this.element.dataset.retryError
    } else if ((result.changed || result.frame.dataset.generation === generation) && this.#apply(result.frame)) {
      this.schedule()
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

  async #requestRetry(url, body, signal) {
    try {
      const response = await fetch(url, {
        method: "POST", body, cache: "no-store", redirect: "error", signal,
        headers: { Accept: "text/html", "Turbo-Frame": this.element.id }
      })
      if (!response.ok && response.status !== 409) return

      const frame = this.#frameFrom(await response.text())
      if (frame) return { frame, changed: response.status === 409 }
    } catch {
      // A failed request never hands this form or its response to Turbo navigation.
    }
  }

  #finishRetry() {
    this.retry.button?.removeAttribute("aria-disabled")
    this.element.removeAttribute("aria-busy")
    this.retry = null
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
    return template.content.querySelector("turbo-frame.n-notes-index-status")
  }

  #apply(frame, { fromSave = false } = {}) {
    const { statusUrl, revision, generation, updatedAt } = frame.dataset
    const current = this.element.dataset
    // Only this editor's first save can turn its blank frame into a persisted one.
    const firstSave = !current.statusUrl && fromSave
    if (!this.element.isConnected || !statusUrl) return false
    if (!firstSave && (current.statusUrl !== statusUrl || this.element.id !== frame.id)) return false

    // A poll or retry may have started before a newer save was acknowledged.
    // On the same revision, indexing itself can have updated the saved state.
    if (BigInt(revision) < BigInt(current.revision) ||
        BigInt(generation) < BigInt(current.generation) ||
        (revision === current.revision && generation === current.generation && updatedAt < current.updatedAt)) return false

    const message = frame.querySelector("[data-note-index-status]")
    const state = message.dataset.noteIndexStatus
    const generationChanged = current.generation !== generation
    const focused = this.actionsTarget.contains(document.activeElement)
    if (firstSave) this.element.id = frame.id
    Object.assign(current, { statusUrl, revision, generation, updatedAt })
    this.messageTarget.dataset.noteIndexStatus = state
    if (this.messageTarget.textContent !== message.textContent) this.messageTarget.textContent = message.textContent
    const outcome = frame.querySelector('[data-note-index-status-target="outcome"]').textContent
    if (this.outcomeTarget.textContent !== outcome) this.outcomeTarget.textContent = outcome
    if (Boolean(this.actionsTarget.firstElementChild) !== (state === "failed") || (state === "failed" && generationChanged)) {
      this.actionsTarget.replaceChildren(...frame.querySelector('[data-note-index-status-target="actions"]').children)
      if (focused) (this.actionsTarget.querySelector("button") || this.messageTarget).focus({ preventScroll: true })
    }
    return true
  }
}
