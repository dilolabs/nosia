import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

// Replaces chat_input_controller for the Lexxy editor. Enter-to-send, URL→Website
// interception, PDF→Document interception, and accumulation of attached source
// ids into hidden form fields. The /skill palette is ported in Task 13.
export default class extends Controller {
  static targets = ["editor", "websiteIds", "documentIds"]

  connect() {
    this.boundInsertLink = this.onInsertLink.bind(this)
    this.boundUploadEnd = this.onUploadEnd.bind(this)
    this.boundHandleKeys = this.handleKeys.bind(this)
    this.sentSgids = new Set()

    this.editorTarget.addEventListener("lexxy:insert-link", this.boundInsertLink)
    this.editorTarget.addEventListener("lexxy:upload-end", this.boundUploadEnd)
    this.editorTarget.addEventListener("keydown", this.boundHandleKeys)
  }

  disconnect() {
    this.editorTarget.removeEventListener("lexxy:insert-link", this.boundInsertLink)
    this.editorTarget.removeEventListener("lexxy:upload-end", this.boundUploadEnd)
    this.editorTarget.removeEventListener("keydown", this.boundHandleKeys)
  }

  // Enter sends; Shift/Meta/Ctrl+Enter fall through so the editor (or a form
  // controller binding meta/ctrl+enter) can handle them. The controller may be
  // attached to the <form> or to a wrapper div inside it, so resolve the form
  // before submitting.
  handleKeys(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.metaKey && !event.ctrlKey) {
      event.preventDefault()
      const form = this.element.tagName === "FORM" ? this.element : this.element.closest("form")
      if (form) form.requestSubmit()
    }
  }

  // Lexxy dispatches lexxy:insert-link on the editor with detail.url when a URL
  // is pasted/linked. Record a Website for it; Lexxy keeps its own <a href>.
  async onInsertLink(event) {
    const url = event.detail.url
    if (!url) return

    const response = await post("/chat_sources", {
      body: JSON.stringify({ url }),
      headers: { "Content-Type": "application/json", "Accept": "application/json" }
    })
    if (response.ok) {
      const data = await response.json
      this.addId(this.websiteIdsTarget, data.id)
    }
  }

  // Lexxy dispatches lexxy:upload-end with { file, error } — the blob's
  // attachable sgid is NOT in the event. It lands on the embedded
  // <action-text-attachment sgid="..."> node a tick later, once editor.update()
  // commits the replacement. Poll for an unregistered sgid, then record a
  // Document for it. (One PDF per paste is the common case; the sentSgids guard
  // keeps us from double-registering on re-fire.)
  async onUploadEnd(event) {
    if (event.detail.error) return

    const sgid = await this.nextUnsentAttachmentSgid()
    if (!sgid) return
    this.sentSgids.add(sgid)

    const response = await post("/chat_sources", {
      body: JSON.stringify({ attachable_sgid: sgid }),
      headers: { "Content-Type": "application/json", "Accept": "application/json" }
    })
    if (response.ok) {
      const data = await response.json
      this.addId(this.documentIdsTarget, data.id)
    }
  }

  nextUnsentAttachmentSgid() {
    return new Promise(resolve => {
      let attempts = 0
      const check = () => {
        const nodes = this.editorTarget.querySelectorAll("action-text-attachment")
        for (const node of nodes) {
          const sgid = node.getAttribute("sgid")
          if (sgid && !this.sentSgids.has(sgid)) return resolve(sgid)
        }
        if (++attempts > 20) {
          console.warn("[composer] lexxy:upload-end fired but no action-text-attachment sgid appeared in time; PDF not registered.")
          return resolve(null)
        }
        requestAnimationFrame(check)
      }
      check()
    })
  }

  // Clone the target hidden input's name so ids submit in the right params
  // namespace (chat[attached_website_ids][] vs message[attached_website_ids][]).
  addId(target, id) {
    if (!id) return
    if (!target.name) {
      console.warn("[composer] hidden id target has no name attribute; attachment not submitted.")
      return
    }
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = target.name
    input.value = id
    target.parentNode.appendChild(input)
  }
}
