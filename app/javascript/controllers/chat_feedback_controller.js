import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { completed: String, stopped: String }

  connect() {
    this.state = this.element.chatFeedbackState ||= { generating: this.busy, phase: null }
    this.observer = new MutationObserver(() => this.update())
    this.observer.observe(this.element, {
      childList: true, subtree: true, attributes: true,
      attributeFilter: ["data-generation-busy", "data-chat-generation-stopped"]
    })
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
  }

  update() {
    const busy = this.busy
    // A newly busy server-rendered composer starts a fresh turn, clearing the old stop.
    if (busy && !this.state.generating && this.element.dataset.chatGenerationStopped === "true") {
      this.element.dataset.chatGenerationStopped = "false"
    }
    if (this.state.generating && !busy) {
      this.announce(this.element.dataset.chatGenerationStopped === "true" ? this.stoppedValue : this.completedValue)
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

  get busy() {
    return !!this.element.querySelector('[data-generation-busy="true"]')
  }
}
