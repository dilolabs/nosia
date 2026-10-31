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
    this.boundRefreshVisit = this.refreshVisit.bind(this)
    this.boundPrepareRefresh = this.prepareRefresh.bind(this)
    this.boundRestoreRefresh = this.restoreRefresh.bind(this)
    this.boundCancelRefresh = this.cancelRefresh.bind(this)
  }

  connect() {
    document.addEventListener("turbo:render", this.boundSyncControls)
    document.addEventListener("turbo:before-visit", this.boundRefreshVisit)
    document.addEventListener("turbo:before-render", this.boundPrepareRefresh)
    this.element.addEventListener("lexxy:initialize", this.boundRestoreRefresh)
    this.element.addEventListener("lexxy:change", this.boundCancelRefresh)
    this.sourceObserver = new MutationObserver(() => {
      if ([...this.sources.keys()].some(source => !this.element.contains(source))) this.syncControls()
    })
    this.sourceObserver.observe(this.element, { childList: true, subtree: true })
    this.stopSwitching()
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundSyncControls)
    document.removeEventListener("turbo:before-visit", this.boundRefreshVisit)
    document.removeEventListener("turbo:before-render", this.boundPrepareRefresh)
    this.element.removeEventListener("lexxy:initialize", this.boundRestoreRefresh)
    this.element.removeEventListener("lexxy:change", this.boundCancelRefresh)
    this.cancelRefresh()
    this.sourceObserver.disconnect()
    this.stopSwitching()
  }

  formTargetConnected() {
    this.submitting = false
    this.syncControls()
  }

  formTargetDisconnected() {
    this.cancelRefresh()
  }

  sendTargetConnected() {
    this.syncControls()
  }

  editingToolsTargetConnected() {
    this.syncControls()
  }

  submitStarted(event) {
    if (event.target !== this.formTarget) return

    this.cancelRefresh()
    this.submitting = true
    this.syncControls()
  }

  submitEnded(event) {
    if (event.target !== this.formTarget) return

    this.submitting = false
    this.syncControls()
  }

  sourceState(event) {
    if (event.detail.pending || event.detail.failed || event.detail.dirty) this.cancelRefresh()
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
    if (this.refreshDraft && (!this.hasFormTarget || this.formTarget.querySelector("lexxy-editor") !== this.refreshDraft.editor)) this.cancelRefresh()
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

  refreshVisit(event) {
    this.cancelRefresh()
    if (event.detail.url === location.href) this.refreshURL = location.href
  }

  prepareRefresh(event) {
    const url = this.refreshURL
    this.cancelRefresh()
    if (!url || url !== location.href || event.detail.renderMethod !== "morph" || !this.refreshEligible) return

    const root = event.detail.newBody.querySelector(`#${CSS.escape(this.element.id)}`)
    const form = root?.querySelector("[data-chat-followup]")
    const editor = this.formTarget.querySelector("lexxy-editor")
    const incoming = form?.querySelector("lexxy-editor")
    const composer = editor?.closest("[data-composer-sources-chat-id-value]")
    const nextComposer = incoming?.closest("[data-composer-sources-chat-id-value]")
    if (!editor || !incoming || !composer?.dataset.composerSourcesChatIdValue || !nextComposer ||
        root.dataset.chatAccountAccountIdValue !== this.accountIdValue ||
        nextComposer.dataset.composerSourcesAccountIdValue !== this.accountIdValue ||
        composer.dataset.composerSourcesAccountIdValue !== this.accountIdValue ||
        nextComposer.dataset.composerSourcesChatIdValue !== composer.dataset.composerSourcesChatIdValue ||
        incoming.id !== editor.id || incoming.getAttribute("name") !== editor.getAttribute("name") ||
        new URL(form.getAttribute("action"), url).href !== this.formTarget.action || form.method !== this.formTarget.method ||
        !root.matches(".n-chat-workspace--saved") || root.querySelector("[data-chat-account-target~=picker]") ||
        !["true", "false"].includes(form.dataset.generationBusy) ||
        incoming.getAttribute("value") || incoming.getAttribute("aria-invalid") === "true" || form.querySelector(".n-composer-validation")) return

    // Lexxy disposes before caching, then reconnects after morph. Its public
    // serialized value survives until that reconnect; never put it in the cache.
    const html = editor.value
    const document = new DOMParser().parseFromString(html || "", "text/html")
    if (!document.body.textContent.trim() || document.querySelector("action-text-attachment, figure, img, video, audio, iframe, [sgid]")) return

    this.refreshDraft = { url, editor, form: this.formTarget, composer, html,
      rootId: this.element.id, chatId: composer.dataset.composerSourcesChatIdValue,
      editorId: editor.id, name: editor.getAttribute("name"), action: this.formTarget.action }
  }

  get refreshEligible() {
    return this.element.isConnected && this.element.matches(".n-chat-workspace--saved[id]") &&
      !this.hasPickerTarget && this.hasFormTarget && !this.submitting && !this.navigating &&
      !this.sourceStates.some(state => state.pending || state.failed || state.dirty) &&
      ![...this.formTarget.querySelectorAll("input[name*='[attached_website_ids]'], input[name*='[attached_document_ids]']")].some(input => input.value)
  }

  restoreRefresh(event) {
    const draft = this.refreshDraft
    this.cancelRefresh()
    if (!draft || !this.refreshEligible || draft.url !== location.href || event.target !== draft.editor ||
        this.formTarget !== draft.form || this.formTarget.querySelector("lexxy-editor") !== draft.editor ||
        this.element.id !== draft.rootId || this.formTarget.action !== draft.action ||
        draft.editor.id !== draft.editorId || draft.editor.getAttribute("name") !== draft.name ||
        !draft.editor.isConnected || !this.element.contains(draft.editor) ||
        draft.editor.closest("[data-composer-sources-chat-id-value]") !== draft.composer ||
        draft.composer.dataset.composerSourcesChatIdValue !== draft.chatId ||
        draft.composer.dataset.composerSourcesAccountIdValue !== this.accountIdValue) return

    // A native change cancels the handoff; also refuse to overwrite nonempty
    // initialized content. Only the editor API updates its form-associated value.
    const current = new DOMParser().parseFromString(draft.editor.value || "", "text/html")
    if (current.body.textContent.trim() || current.querySelector("action-text-attachment, a[href], img")) return

    draft.editor.value = draft.html
  }

  cancelRefresh() {
    this.refreshURL = null
    this.refreshDraft = null
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
    this.cancelRefresh()
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
