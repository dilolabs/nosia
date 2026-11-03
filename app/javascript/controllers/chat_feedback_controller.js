import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { completed: String, stopped: String }

  connect() {
    this.state = this.element.chatFeedbackState ||= { generating: this.generation?.busy, phase: null }
    this.observer = new MutationObserver(() => this.update())
    this.observer.observe(this.element, {
      childList: true, subtree: true, attributes: true,
      attributeFilter: ["data-generation-busy", "data-generation-stopped"]
    })
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
  }

  update() {
    const generation = this.generation
    if (!generation) return

    const { busy, stopped } = generation
    if (this.state.generating && !busy) {
      this.announce(stopped ? this.stoppedValue : this.completedValue)
      this.state.phase = null
    } else if (busy) {
      const phase = [...this.element.querySelectorAll(".n-chat-phase[data-phase]")].at(-1)
      if (phase && phase.dataset.phase !== this.state.phase) {
        this.state.phase = phase.dataset.phase
        this.announce(phase.querySelector(".n-chat-phase-title").textContent.trim())
      }
    }
    this.state.generating = busy
  }

  announce(text) {
    if (this.statusTarget.textContent !== text) this.statusTarget.textContent = text
  }

  get generation() {
    const form = this.element.querySelector("form[data-chat-followup]")
    if (form && ["true", "false"].includes(form.dataset.generationBusy) && ["true", "false"].includes(form.dataset.generationStopped)) {
      return { busy: form.dataset.generationBusy === "true", stopped: form.dataset.generationStopped === "true" }
    }
  }
}
