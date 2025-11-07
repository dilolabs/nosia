import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "phase", "subtext"]

  connect() {
    this.phases = [
      { text: "Searching...", subtext: "Looking for relevant information", duration: 2000 },
      { text: "Thinking...", subtext: "Analyzing and reasoning", duration: 3000 },
      { text: "Generating...", subtext: "Crafting the response", duration: 2000 }
    ]
    this.currentPhaseIndex = 0
    this.startAnimation()
  }

  disconnect() {
    this.stopAnimation()
  }

  startAnimation() {
    // Display the first phase immediately
    this.updatePhase(0)

    // Schedule the next transitions
    this.scheduleNextPhase()
  }

  scheduleNextPhase() {
    const currentPhase = this.phases[this.currentPhaseIndex]

    this.phaseTimeout = setTimeout(() => {
      this.currentPhaseIndex = (this.currentPhaseIndex + 1) % this.phases.length
      this.transitionToPhase(this.currentPhaseIndex)
      this.scheduleNextPhase()
    }, currentPhase.duration)
  }

  transitionToPhase(index) {
    // Fade out
    this.phaseTarget.style.opacity = "0"
    this.subtextTarget.style.opacity = "0"

    // Wait for the fade-out animation to complete (300ms)
    setTimeout(() => {
      this.updatePhase(index)

      // Fade in
      setTimeout(() => {
        this.phaseTarget.style.opacity = "1"
        this.subtextTarget.style.opacity = "1"
      }, 50)
    }, 300)
  }

  updatePhase(index) {
    const phase = this.phases[index]
    this.phaseTarget.textContent = phase.text
    this.subtextTarget.textContent = phase.subtext
  }

  stopAnimation() {
    if (this.phaseTimeout) {
      clearTimeout(this.phaseTimeout)
      this.phaseTimeout = null
    }
  }

  // Method to smoothly fade out the animation
  fadeOut() {
    this.stopAnimation()
    this.containerTarget.style.opacity = "0"
    this.containerTarget.style.transform = "translateY(-10px)"

    setTimeout(() => {
      this.containerTarget.remove()
    }, 300)
  }
}
