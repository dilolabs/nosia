import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { fillMessage } from "controllers/note_import_preview"

const POLL_MS = 2000
const TIMEOUT_MS = 15_000
const TERMINAL = ["succeeded", "failed", "expired"]

export default class extends Controller {
  static targets = ["message", "progress"]
  static values = { url: String, pollError: String, progress: String }

  connect() { this.schedule() }
  disconnect() { this.stop() }

  schedule() {
    if (!this.timer && !this.poll && !this.finished) {
      this.timer = setTimeout(() => this.#refresh(), POLL_MS)
    }
  }

  stop() {
    clearTimeout(this.timer)
    clearTimeout(this.timeout)
    const poll = this.poll
    this.timer = this.poll = null
    poll?.abort()
  }

  async #refresh() {
    this.timer = null
    const poll = this.poll = new AbortController()
    this.timeout = setTimeout(() => poll.abort(), TIMEOUT_MS)
    try {
      const response = await fetch(this.urlValue, {
        cache: "no-store", redirect: "error", credentials: "same-origin", signal: poll.signal,
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new TypeError()

      const result = await response.json()
      if (this.poll !== poll || !this.element.isConnected) return

      const { status, message, uploaded_count: uploaded, total, result_url: resultUrl } = result
      if (TERMINAL.includes(status)) {
        this.finished = true
        if (status === "succeeded" && resultUrl) {
          Turbo.visit(resultUrl)
        } else {
          Turbo.visit(this.urlValue, { action: "replace" })
        }
      } else {
        const progress = fillMessage(this.progressValue, { uploaded, total })
        if (this.messageTarget.textContent !== message) this.messageTarget.textContent = message
        if (this.progressTarget.textContent !== progress) this.progressTarget.textContent = progress
      }
    } catch {
      if (this.poll === poll && this.element.isConnected) {
        this.finished = true
        this.messageTarget.textContent = this.pollErrorValue
      }
    } finally {
      if (this.poll === poll) {
        clearTimeout(this.timeout)
        this.poll = null
        this.schedule()
      }
    }
  }
}
