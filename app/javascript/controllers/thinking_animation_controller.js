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
    // Afficher la première phase immédiatement
    this.updatePhase(0)

    // Programmer les transitions suivantes
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

    // Attendre la fin de l'animation de fade out (300ms)
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

  // Méthode pour faire disparaître l'animation en douceur
  fadeOut() {
    this.stopAnimation()
    this.containerTarget.style.opacity = "0"
    this.containerTarget.style.transform = "translateY(-10px)"

    setTimeout(() => {
      this.containerTarget.remove()
    }, 300)
  }
}
