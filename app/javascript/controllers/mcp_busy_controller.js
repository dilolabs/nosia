import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() { this.pending = new Map() }

  start(event) {
    const form = event.target
    if (!form.matches("[data-mcp-operation]")) return
    const group = form.closest("[data-mcp-busy-group]")
    if (!group) return
    const submitter = event.detail.formSubmission.submitter
    const states = Array.from(group.querySelectorAll("button,input[type=submit]"))
      .filter(button => button !== submitter).map(button => [button, button.disabled])
    this.pending.set(form, { group, states })
    states.forEach(([button]) => button.disabled = true)
    group.setAttribute("aria-busy", "true")
  }

  finish(event) { this.restore(event.target) }

  disconnect() { this.pending?.forEach((_, form) => this.restore(form)) }

  restore(form) {
    const entry = this.pending.get(form)
    if (!entry) return
    entry.states.forEach(([button, disabled]) => button.disabled = disabled)
    entry.group.removeAttribute("aria-busy")
    this.pending.delete(form)
  }
}
