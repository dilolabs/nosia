import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { fillMessage, previewFolder } from "controllers/note_import_preview"
import { uploadFolder, UploadRejection } from "controllers/note_import_upload"

const UPLOAD_TIMEOUT_MS = 120_000

export default class extends Controller {
  static targets = ["picker", "status", "error", "confirm", "review", "find"]
  static values = { url: String, limits: Object, messages: Object }

  connect() {
    this.confirmLabel = this.confirmTarget.textContent.trim()
    this.supported = "webkitdirectory" in this.pickerTarget && typeof crypto.randomUUID === "function"
    this.clear()
  }

  disconnect() { this.#abort() }

  clear() {
    this.#abort()
    this.pickerTarget.value = ""
    this.pickerTarget.disabled = !this.supported
    this.statusTarget.textContent = this.messagesValue[this.supported ? "ready" : "unsupported"]
    this.confirmTarget.disabled = true
    this.confirmTarget.textContent = this.confirmLabel
    this.#showError()
  }

  select() {
    this.#abort()
    this.confirmTarget.disabled = true
    this.confirmTarget.textContent = this.confirmLabel
    this.statusTarget.textContent = this.messagesValue.ready
    this.#showError()
    if (!this.pickerTarget.files.length) return

    const { error, ...selection } = previewFolder(this.pickerTarget.files, this.limitsValue)
    if (error) {
      this.pickerTarget.value = ""
      this.#showError(this.messagesValue[error])
    } else {
      const { root, entries, folders, ignored } = selection
      this.selection = { ...selection, key: crypto.randomUUID() }
      this.statusTarget.textContent = fillMessage(this.messagesValue.preview, { root, notes: entries.size, folders, ...ignored })
      this.confirmTarget.disabled = false
    }
  }

  async confirm() {
    if (!this.selection || this.upload) return

    const upload = this.upload = new AbortController()
    this.timeout = setTimeout(() => upload.abort(), UPLOAD_TIMEOUT_MS)
    this.pickerTarget.disabled = this.confirmTarget.disabled = true
    this.#showError()
    this.#progress(0, this.selection.entries.size)
    try {
      const url = await uploadFolder(this.urlValue, this.selection, this.limitsValue, upload.signal, (uploaded, total) => {
        if (this.upload === upload) this.#progress(uploaded, total)
      })
      if (this.upload === upload && this.element.isConnected) Turbo.visit(url)
    } catch (error) {
      if (this.upload === upload && this.element.isConnected) this.#failed(error)
    } finally {
      if (this.upload === upload) {
        clearTimeout(this.timeout)
        this.upload = null
      }
    }
  }

  #abort() {
    clearTimeout(this.timeout)
    const upload = this.upload
    this.selection = this.upload = null
    upload?.abort()
  }

  #progress(uploaded, total) {
    this.statusTarget.textContent = fillMessage(this.messagesValue.uploading, { uploaded, total })
  }

  #failed(error) {
    const messages = this.messagesValue
    const retryable = !(error instanceof UploadRejection) || error.status >= 500 ||
      [408, 429].includes(error.status) || ["incomplete_upload", "not_uploading"].includes(error.code)
    this.pickerTarget.disabled = false
    this.confirmTarget.disabled = !retryable
    this.statusTarget.textContent = ""
    if (retryable) {
      this.confirmTarget.textContent = messages.retry_button
      this.#showError(messages.retry_hint)
    } else {
      this.selection = null
      this.pickerTarget.value = ""
      const message = error.status === 413 ? messages.too_large : error.code && error.message
      if (error.code === "import_in_progress") {
        this.#showError(message || messages.rejected)
        this.findTarget.hidden = false
      } else {
        this.#showError(`${message || messages.rejected} ${error.receiptUrl ? messages.review : messages.restart}`)
        if (error.receiptUrl) {
          this.reviewTarget.href = error.receiptUrl
          this.reviewTarget.hidden = false
        }
      }
    }
  }

  #showError(message) {
    this.reviewTarget.hidden = this.findTarget.hidden = true
    this.reviewTarget.removeAttribute("href")
    this.errorTarget.textContent = message || ""
    this.errorTarget.hidden = !message
    if (message) this.errorTarget.focus()
  }
}
