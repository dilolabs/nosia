import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { post, UploadRejection } from "controllers/note_import_upload"

export default class extends Controller {
  static targets = ["button", "error"]
  static values = { url: String, receipt: String, confirm: String, error: String }

  connect() { this.buttonTarget.disabled = false }
  disconnect() { this.stop() }

  stop() {
    clearTimeout(this.timeout)
    const request = this.request
    this.request = null
    request?.abort()
    if (this.hasButtonTarget) this.buttonTarget.disabled = false
  }

  async discard() {
    if (this.request || !window.confirm(this.confirmValue)) return

    const request = this.request = new AbortController()
    this.timeout = setTimeout(() => request.abort(), 15_000)
    this.errorTarget.hidden = true
    this.buttonTarget.disabled = true
    try {
      await post(this.urlValue, {}, request.signal)
      if (this.request === request && this.element.isConnected) Turbo.visit(this.receiptValue, { action: "replace" })
    } catch (error) {
      if (this.request === request && this.element.isConnected) {
        this.errorTarget.textContent = error instanceof UploadRejection && error.status === 409 ? error.message : this.errorValue
        this.errorTarget.hidden = false
        this.errorTarget.focus()
      }
    } finally {
      if (this.request === request) this.stop()
    }
  }
}
