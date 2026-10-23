import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["picker", "form", "send", "editingTools"]
  static values = { accountId: String, confirmMessage: String }

  initialize() {
    this.sources = new Map()
    this.submitting = false
    this.switching = false
    this.boundSyncControls = this.syncControls.bind(this)
  }

  connect() {
    document.addEventListener("turbo:render", this.boundSyncControls)
    this.sourceObserver = new MutationObserver(() => {
      if ([...this.sources.keys()].some(source => !this.element.contains(source))) this.syncControls()
    })
    this.sourceObserver.observe(this.element, { childList: true, subtree: true })
    this.stopSwitching()
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundSyncControls)
    this.sourceObserver.disconnect()
    this.stopSwitching()
  }

  formTargetConnected() {
    this.submitting = false
    this.syncControls()
  }

  sendTargetConnected() {
    this.syncControls()
  }

  editingToolsTargetConnected() {
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

  get navigating() {
    return this.switching || document.documentElement.hasAttribute("data-turbo-preview")
  }

  syncControls() {
    this.element.inert = this.navigating

    if (this.hasPickerTarget) {
      this.pickerTarget.disabled = this.navigating || this.pending || this.submitting
    }

    if (this.hasFormTarget) {
      const editorLocked = this.navigating || this.submitting || this.formTarget.dataset.generationBusy === "true"
      const editor = this.formTarget.querySelector("lexxy-editor")
      if (editor) {
        editor.toggleAttribute("disabled", editorLocked)
        editor.inert = editorLocked
      }

      for (const group of this.editingToolsTargets) {
        group.inert = editorLocked
        group.setAttribute("aria-disabled", String(editorLocked))
        for (const button of group.querySelectorAll("button")) button.disabled = editorLocked
      }

      if (this.hasSendTarget) {
        this.sendTarget.disabled = editorLocked || this.pending || this.failed
      }
    }
  }

  guard(event) {
    if (this.navigating || this.pending || this.failed || this.submitting || this.formTarget.dataset.generationBusy === "true") {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }

  change() {
    const next = this.pickerTarget.value

    if (this.navigating || this.pending || this.submitting || next === this.accountIdValue) {
      this.pickerTarget.value = this.accountIdValue
      return
    }

    if (this.dirty() && !window.confirm(this.confirmMessageValue)) {
      this.pickerTarget.value = this.accountIdValue
      return
    }

    const url = new URL(window.location.href)
    url.searchParams.set("account_id", next)
    this.startSwitching(url)
    Turbo.visit(url.toString())
  }

  startSwitching(url) {
    this.switching = true
    const navigation = new AbortController()
    this.switchNavigation = navigation
    const { signal } = navigation

    document.addEventListener("turbo:before-visit", event => {
      if (event.detail.url !== url.href) return

      // Later listeners (including window listeners) can still cancel this visit.
      queueMicrotask(() => {
        if (event.defaultPrevented && this.switchNavigation === navigation) this.stopSwitching()
      })
    }, { signal })

    document.addEventListener("turbo:fetch-request-error", event => {
      if (event.target !== document.documentElement || event.detail.request.url.href !== url.href) return

      // The confirmed draft must not survive Turbo's full-page recovery.
      this.resetDraft()
    }, { signal })

    this.syncControls()
  }

  stopSwitching() {
    this.switchNavigation?.abort()
    this.switchNavigation = null
    this.switching = false
    if (this.hasPickerTarget) this.pickerTarget.value = this.accountIdValue
    this.syncControls()
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
    this.resetDraft()
  }

  resetDraft() {
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

    this.sources.clear()
    this.submitting = false
    this.stopSwitching()
  }
}
