import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["editor", "websiteIds", "documentIds", "errors"]
  static values = { accountId: String, chatId: String }

  connect() {
    this.operations = new Map()
    this.uploads = new Set()
    this.sentSgids = new Set()
    this.dirty = false
    this.onLink = event => this.register({ url: event.detail.url }, "websiteIds", `url:${event.detail.url}`)
    this.onStart = event => {
      if (this.entryBlocked) return

      this.uploads.add(event.detail.file)
      this.dirty = true
      this.publishState()
    }
    this.onEnd = event => this.uploadEnded(event)

    this.editorTarget.addEventListener("lexxy:insert-link", this.onLink)
    this.editorTarget.addEventListener("lexxy:upload-start", this.onStart)
    this.editorTarget.addEventListener("lexxy:upload-end", this.onEnd)
    queueMicrotask(() => this.publishState())
  }

  disconnect() {
    this.editorTarget.removeEventListener("lexxy:insert-link", this.onLink)
    this.editorTarget.removeEventListener("lexxy:upload-start", this.onStart)
    this.editorTarget.removeEventListener("lexxy:upload-end", this.onEnd)
    for (const operation of this.operations.values()) operation.controller?.abort()
    this.uploads.clear()
  }

  async uploadEnded(event) {
    const { file, error } = event.detail
    if (!this.uploads.has(file)) return

    try {
      if (error) throw new Error("PDF upload failed. Reset the draft and attach it again.")

      const sgid = await this.nextSgid(file)
      if (!this.uploads.has(file) || !this.element.isConnected) return
      if (!sgid) throw new Error("The PDF could not be registered. Reset the draft and attach it again.")

      this.register({ attachable_sgid: sgid }, "documentIds", `sgid:${sgid}`)
    } catch (failure) {
      if (!this.uploads.has(file) || !this.element.isConnected) return

      this.operations.set(file, { failed: true, pending: false, message: failure.message })
      this.renderErrors()
    } finally {
      this.uploads.delete(file)
      this.publishState()
    }
  }

  // Lexxy emits upload-end before the serialized attachment SGID is committed.
  // The live attachment DOM does not contain the SGID; read the exported value.
  nextSgid(file) {
    return new Promise(resolve => {
      let attempts = 0
      const check = () => {
        if (!this.element.isConnected || !this.uploads.has(file)) return resolve(null)

        const document = new DOMParser().parseFromString(this.editorTarget.value || "", "text/html")
        for (const node of document.querySelectorAll("action-text-attachment[sgid]")) {
          const sgid = node.getAttribute("sgid")
          if (!this.sentSgids.has(sgid)) {
            this.sentSgids.add(sgid)
            return resolve(sgid)
          }
        }
        if (++attempts >= 20) return resolve(null)

        requestAnimationFrame(check)
      }
      check()
    })
  }

  register(payload, target, key) {
    if (this.entryBlocked || (!payload.url && !payload.attachable_sgid) || this.operations.has(key)) return

    const context = this.chatIdValue ? { chat_id: this.chatIdValue } : { account_id: this.accountIdValue }
    const operation = { payload: { ...payload, ...context }, target, pending: false, failed: false }
    this.operations.set(key, operation)
    this.dirty = true
    this.run(operation)
  }

  async run(operation) {
    if (this.entryBlocked || operation.pending) return

    operation.pending = true
    operation.failed = false
    const controller = new AbortController()
    operation.controller = controller
    this.renderErrors()
    this.publishState()

    try {
      const response = await post("/chat_sources", {
        body: JSON.stringify(operation.payload),
        signal: controller.signal,
        headers: { "Content-Type": "application/json", "Accept": "application/json" }
      })
      let data
      try {
        data = await response.json
      } catch {
        data = {}
      }
      if (controller.signal.aborted || !this.element.isConnected) return
      if (!response.ok || !data.id) throw new Error(data.error || "Source registration failed. Retry or reset the draft.")

      this.addId(this[`${operation.target}Target`], data.id)
    } catch (failure) {
      if (!controller.signal.aborted && this.element.isConnected && failure.name !== "AbortError") {
        operation.failed = true
        operation.message = failure.message || "Source registration failed."
      }
    } finally {
      operation.pending = false
      if (!controller.signal.aborted && this.element.isConnected) {
        this.renderErrors()
        this.publishState()
      }
    }
  }

  get entryBlocked() {
    return !this.element.isConnected || this.editorTarget.hasAttribute("disabled") || Boolean(this.editorTarget.closest("[inert]"))
  }

  // Keep the hidden input namespace from the rendered chat or message form.
  addId(target, id) {
    if (!target.name) throw new Error("Attachment form is unavailable. Reset the draft.")

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = target.name
    input.value = id
    target.parentNode.appendChild(input)
  }

  renderErrors() {
    this.errorsTarget.replaceChildren()
    const failures = [...this.operations.values()].filter(operation => operation.failed)
    this.errorsTarget.hidden = failures.length === 0

    for (const operation of failures) {
      const row = document.createElement("li")
      row.append(document.createTextNode(operation.message + " "))
      if (operation.payload) {
        const retry = document.createElement("button")
        retry.type = "button"
        retry.textContent = "Retry source"
        retry.addEventListener("click", () => this.run(operation))
        row.append(retry)
      }

      const reset = document.createElement("button")
      reset.type = "button"
      reset.textContent = "Reset draft"
      reset.addEventListener("click", () => {
        if (window.confirm("Reset this unsent draft? Saved sources will remain in their account.")) this.reset()
      })
      row.append(reset)
      this.errorsTarget.append(row)
    }
  }

  reset(event) {
    if (event?.detail?.root && !event.detail.root.contains(this.element)) return

    for (const operation of this.operations.values()) operation.controller?.abort()
    this.uploads.clear()
    this.operations.clear()
    this.sentSgids.clear()
    this.dirty = false
    this.editorTarget.value = ""
    for (const target of [this.websiteIdsTarget, this.documentIdsTarget]) {
      for (const input of target.parentNode.querySelectorAll("input")) {
        if (input.name === target.name) input.value = ""
      }
    }
    this.editorTarget.dispatchEvent(new CustomEvent("lexxy:change", { bubbles: true }))
    this.renderErrors()
    this.publishState()
  }

  publishState() {
    if (!this.element.isConnected) return

    const operations = [...this.operations.values()]
    this.dispatch("state", {
      detail: {
        pending: this.uploads.size + operations.filter(operation => operation.pending).length,
        failed: operations.some(operation => operation.failed),
        dirty: this.dirty
      }
    })
  }
}
