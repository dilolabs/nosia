import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["picker", "form", "send"]
  static values = { accountId: String }

  initialize() {
    this.sources = new Map()
    this.submitting = false
  }

  connect() {
    this.syncControls()
  }

  formTargetConnected() {
    this.submitting = false
    this.syncControls()
  }

  sendTargetConnected() {
    this.syncControls()
  }

  submitStarted(event) {
    if (event.target !== this.formTarget) return

    this.submitting = true
    this.syncControls()
  }

  submitEnded(event) {
    if (event.target !== this.formTarget) return

    this.submitting = false
    this.syncControls()
  }

  sourceState(event) {
    this.sources.set(event.target, event.detail)
    this.syncControls()
  }

  get sourceStates() {
    for (const element of this.sources.keys()) {
      if (!this.element.contains(element)) this.sources.delete(element)
    }

    return [...this.sources.values()]
  }

  get pending() {
    return this.sourceStates.some(state => state.pending > 0)
  }

  get failed() {
    return this.sourceStates.some(state => state.failed)
  }

  syncControls() {
    if (this.hasPickerTarget) {
      this.pickerTarget.disabled = this.pending || this.submitting
    }

    if (this.hasSendTarget && this.hasFormTarget) {
      this.sendTarget.disabled = this.pending || this.failed || this.submitting || this.formTarget.dataset.generationBusy === "true"
    }
  }

  guard(event) {
    if (this.pending || this.failed || this.submitting || this.formTarget.dataset.generationBusy === "true") {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }

  change() {
    const next = this.pickerTarget.value

    if (this.pending || this.submitting || next === this.accountIdValue) {
      this.pickerTarget.value = this.accountIdValue
      return
    }

    if (this.dirty() && !window.confirm("Change account? This clears your unsent message, attachment references, and tool choices. Saved sources remain in the previous account.")) {
      this.pickerTarget.value = this.accountIdValue
      return
    }

    const url = new URL(window.location.href)
    url.searchParams.set("account_id", next)
    Turbo.visit(url.toString())
  }

  dirty() {
    const document = new DOMParser().parseFromString(this.element.querySelector("lexxy-editor")?.value || "", "text/html")

    return Boolean(
      document.body.textContent.trim() ||
      document.querySelector("action-text-attachment, a[href], img") ||
      this.element.querySelector("input[name='mcp_server_ids[]']:checked") ||
      this.sourceStates.some(state => state.dirty || state.failed)
    )
  }

  beforeCache() {
    if (!this.hasPickerTarget) return

    window.dispatchEvent(new CustomEvent("chat-account:reset", { detail: { root: this.element } }))

    const editor = this.element.querySelector("lexxy-editor")
    if (editor) editor.value = ""

    for (const input of this.element.querySelectorAll("input")) {
      if (input.name.includes("attached_website_ids") || input.name.includes("attached_document_ids")) {
        input.value = ""
      }

      if (input.name === "mcp_server_ids[]" && input.type === "checkbox") {
        input.checked = false
      }
    }

    this.element.querySelector("#mcp-server-hidden-fields")?.replaceChildren()
    this.element.querySelector("[data-composer-target='menu']")?.replaceChildren()

    const count = this.element.querySelector("#mcp-selected-count")
    if (count) count.textContent = "0"

    this.pickerTarget.value = this.accountIdValue
    this.sources.clear()
    this.submitting = false
    this.syncControls()
  }
}
