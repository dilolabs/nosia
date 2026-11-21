import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import NoteDeparture from "controllers/note_departure"

const IDLE_MS = 600
const REGIONS = ["notes-list", "notes-sidebar", "notes-editor-heading", "notes-header-actions"]
const MEANINGFUL_TEXT = /[^\p{White_Space}\p{Cc}\p{Cf}]/u

export default class extends Controller {
  static targets = ["editor", "title", "revision", "formatting", "status", "retry", "copy", "load", "copyStatus", "copyText"]
  static values = { messages: Object, recovered: Boolean }

  connect() {
    this.serial = 0
    this.autosavePaused = false
    this.workspace = this.element.closest(".n-notes")
    this.departure = new NoteDeparture(this.element, {
      draftSerial: () => this.dirty ? this.serial : null,
      confirmDiscard: () => this.#confirmDiscard(),
      onFailure: (message) => this.#departureFailed(message),
      onReturn: () => this.#replaceLocation()
    })
    if (this.editorTarget.editor?.getRootElement()) this.hydrate()
    if (this.recoveredValue) this.#markDirty()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
    this.request = null
    this.firstPost = null
    this.departure.disconnect()
    this.content = null
    this.dirty = false
    window.removeEventListener("beforeunload", this.#beforeUnload)
  }

  hydrate() {
    const toolbar = this.editorTarget.toolbarElement
    toolbar.id = this.formattingTarget.getAttribute("aria-controls")
    this.formattingTarget.hidden = false
    this.editorTarget.editorContentElement.classList.add("lexxy-content")
    this.content = this.#readContent()
  }

  toggleFormatting() {
    const open = this.element.toggleAttribute("data-formatting-open")
    this.formattingTarget.setAttribute("aria-expanded", open)
    const toolbar = this.editorTarget.toolbarElement
    if (open) {
      // Lexxy's buttons are not tabbable until its content first gets focus.
      const first = Array.from(toolbar.querySelectorAll("button:not(:disabled)")).find(button => button.getClientRects().length)
      if (first) {
        first.tabIndex = 0
        first.focus()
      }
    } else {
      toolbar.closeDropdowns()
      this.formattingTarget.focus()
    }
  }

  changed(event) {
    if (!this.content || (event.target !== this.titleTarget && !this.editorTarget.contains(event.target))) return

    const content = this.#readContent()
    if (content.title === this.content.title && content.body === this.content.body) return

    this.content = content
    this.#markDirty()
    this.editTime = performance.now()
    if (!this.autosavePaused && !this.request && !this.conflict && !this.retryRequired) {
      this.#showStatus(this.messagesValue.unsaved)
      this.#schedule()
    }
  }

  saveNow(event) {
    if (!this.content) return

    event.preventDefault()
    clearTimeout(this.timer)
    this.autosavePaused = false
    this.#save()
  }

  keyboardSave(event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") this.saveNow(event)
  }

  closeFormatting(event) {
    if (!event.defaultPrevented && this.editorTarget.toolbarElement?.contains(event.target)) this.toggleFormatting()
  }

  async copyDraft() {
    const text = [this.titleTarget.value, this.editorTarget.toString()].filter(Boolean).join("\n\n")
    try {
      await navigator.clipboard.writeText(text)
      if (this.element.isConnected) this.copyStatusTarget.textContent = this.messagesValue.draft_copied
    } catch {
      if (!this.element.isConnected) return

      this.copyTextTarget.value = text
      this.copyTextTarget.hidden = false
      this.copyTextTarget.focus()
      this.copyTextTarget.select()
      this.copyStatusTarget.textContent = this.messagesValue.copy_manually
    }
  }

  loadSaved() {
    if (!this.savedLocation) return

    this.#pauseAutosave()
    this.skipUnloadWarning = true
    // A Turbo morph of the same URL could preserve this conflicted controller.
    window.location.replace(this.savedLocation)
  }

  #readContent() {
    return { title: this.titleTarget.value, body: this.editorTarget.value }
  }

  #markDirty() {
    this.serial += 1
    this.dirty = true
    window.addEventListener("beforeunload", this.#beforeUnload)
  }

  #markClean() {
    this.dirty = false
    window.removeEventListener("beforeunload", this.#beforeUnload)
  }

  #schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#save(), Math.max(0, IDLE_MS - (performance.now() - this.editTime)))
  }

  #snapshot() {
    const body = new FormData(this.element)
    const method = body.get("_method")?.toUpperCase() || "POST"
    if (method === "POST") {
      const text = this.editorTarget.toString().trim()
      const seed = body.get("note[seed_tag]")
      if (!MEANINGFUL_TEXT.test(this.titleTarget.value) &&
          (!MEANINGFUL_TEXT.test(text) || (seed && text === `#${seed}`))) return
    }
    body.delete("_method")
    return { url: this.element.action, method, body, serial: this.serial }
  }

  async #save() {
    if (!this.dirty || this.autosavePaused || this.request || this.conflict) return

    const snapshot = this.firstPost || this.#snapshot()
    if (!snapshot) return
    if (snapshot.method === "POST") this.firstPost = snapshot

    const request = this.request = new AbortController()
    let acknowledged = false
    this.retryRequired = false
    this.#showStatus(this.messagesValue.saving)
    try {
      const { url, method, body } = snapshot
      const response = await fetch(url, {
        method, body, signal: request.signal, redirect: "error",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      const result = [200, 201, 409, 422].includes(response.status) ? await response.json() : null
      if (!this.#currentRequest(request)) return

      if (response.ok && result) {
        this.#accept(result, snapshot.serial)
        acknowledged = true
      } else if (response.status === 409 || response.status === 404) {
        this.#showConflict(result)
      } else if (response.status === 422 && result) {
        this.firstPost = null // Definitive rejection: a corrected POST may reuse the key.
        this.#showStatus(result.message, { retry: true })
      } else {
        this.#failed()
      }
    } catch {
      if (this.#currentRequest(request)) this.#failed()
    } finally {
      if (this.#currentRequest(request)) {
        this.request = null
        if (acknowledged && this.dirty) this.#schedule()
      }
    }
  }

  #currentRequest(request) {
    return this.request === request && this.element.isConnected
  }

  #accept(result, serial) {
    const form = this.element
    if (!form.elements.namedItem("_method")) {
      const method = document.createElement("input")
      Object.assign(method, { type: "hidden", name: "_method", value: "patch" })
      form.append(method)
    }
    this.revisionTarget.value = result.revision
    form.action = result.update_url
    this.firstPost = null
    this.locationToReplace = new URL(result.location, window.location.origin)
    this.#replaceLocation()
    this.#refreshWorkspace(result.workspace)

    if (this.serial === serial) {
      this.#markClean()
      form.querySelector(".n-notes-errors")?.remove()
      this.copyTarget.hidden = this.copyTextTarget.hidden = true
      this.copyStatusTarget.textContent = ""
      this.#showStatus(this.messagesValue.saved)
    } else {
      this.#showStatus(this.messagesValue.unsaved)
    }
  }

  #replaceLocation() {
    if (!this.departure.atEditorEntry || !this.locationToReplace) return

    const { history, view } = Turbo.session
    const location = this.locationToReplace
    this.locationToReplace = null
    if (location.href === window.location.href) return

    history.replace(location, window.history.state?.turbo?.restorationIdentifier)
    view.lastRenderedLocation = location
    const returnTo = document.querySelector(".n-language-preference input[name='return_to']")
    if (returnTo) returnTo.value = location.pathname + location.search
  }

  #refreshWorkspace(regions) {
    const template = document.createElement("template")
    const focusedNote = document.activeElement?.closest("#notes-list [data-note-id] > a")?.parentElement.id
    for (const id of REGIONS) {
      template.innerHTML = regions[id]
      const region = this.workspace.querySelector(`#${id}`)
      region.addEventListener("turbo:before-morph-attribute", this.#preserveInteraction)
      try {
        Turbo.morphElements(region, template.content.firstElementChild, { ignoreActiveValue: true })
      } finally {
        region.removeEventListener("turbo:before-morph-attribute", this.#preserveInteraction)
      }
    }
    if (focusedNote) this.workspace.querySelector(`#${CSS.escape(focusedNote)} > a`)?.focus({ preventScroll: true })
  }

  #preserveInteraction = (event) => {
    const { attributeName, mutationType } = event.detail
    if (mutationType === "remove" &&
        ((attributeName === "open" && event.target.matches("details")) ||
          (attributeName === "aria-haspopup" && event.target.matches(".n-notes-folder-trigger")))) event.preventDefault()
  }

  #failed() {
    this.retryRequired = true
    this.#showStatus(this.messagesValue.save_failed, { retry: true })
  }

  #showConflict(result) {
    this.conflict = true
    this.savedLocation = result?.code === "edit_conflict" ? result.location : null
    this.#showStatus(result?.message || this.messagesValue.unavailable)
    this.copyTarget.hidden = false
    this.loadTarget.hidden = !this.savedLocation
  }

  #showStatus(message, { retry = false } = {}) {
    if (this.statusTarget.textContent !== message) this.statusTarget.textContent = message
    if (!retry && document.activeElement === this.retryTarget) this.titleTarget.focus({ preventScroll: true })
    this.retryTarget.hidden = !retry
  }

  #confirmDiscard() {
    if (!window.confirm(this.messagesValue.discard_draft)) return false

    this.#pauseAutosave()
    return true
  }

  #departureFailed(message) {
    this.#pauseAutosave()
    this.#showStatus(this.messagesValue[message])
    this.copyTarget.hidden = false
  }

  #pauseAutosave() {
    // Approval stops background writes, not the dirty warning. If we never
    // leave the page, the draft must still be available for an explicit save.
    this.autosavePaused = true
    clearTimeout(this.timer)
    this.request?.abort()
    this.request = null
    if (!this.conflict) this.#showStatus(this.messagesValue.unsaved)
  }

  #beforeUnload = (event) => {
    if (this.skipUnloadWarning) {
      this.skipUnloadWarning = false
      return
    }

    event.preventDefault()
    event.returnValue = true
  }
}
