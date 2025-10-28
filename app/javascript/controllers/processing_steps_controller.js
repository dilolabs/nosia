import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "spinner"]
  static values = { 
    steps: Array,
    currentStep: Number,
    isProcessing: Boolean
  }

  connect() {
    this.currentStepValue = 0
    this.isProcessingValue = false
    this.stepsValue = ["Reasoning", "Context", "Search", "Generating"]
  }

  startProcessing() {
    this.isProcessingValue = true
    this.currentStepValue = 0
    this.updateSteps()
    this.animateSteps()
  }

  stopProcessing() {
    this.isProcessingValue = false
    this.updateSteps()
  }

  animateSteps() {
    if (!this.isProcessingValue) return

    const interval = setInterval(() => {
      if (!this.isProcessingValue) {
        clearInterval(interval)
        return
      }

      this.currentStepValue = (this.currentStepValue + 1) % this.stepsValue.length
      this.updateSteps()
    }, 1500) // Change d'étape toutes les 1.5 secondes
  }

  updateSteps() {
    this.stepTargets.forEach((step, index) => {
      const stepElement = step.querySelector('.step-indicator')
      const stepText = step.querySelector('.step-text')
      
      if (index === this.currentStepValue && this.isProcessingValue) {
        stepElement.classList.remove('opacity-50', 'bg-gray-400')
        stepElement.classList.add('opacity-100', 'bg-blue-500', 'animate-pulse')
        stepText.classList.remove('opacity-50')
        stepText.classList.add('opacity-100')
      } else if (index < this.currentStepValue) {
        stepElement.classList.remove('opacity-50', 'bg-gray-400', 'animate-pulse')
        stepElement.classList.add('opacity-100', 'bg-green-500')
        stepText.classList.remove('opacity-50')
        stepText.classList.add('opacity-100')
      } else {
        stepElement.classList.remove('opacity-100', 'bg-blue-500', 'bg-green-500', 'animate-pulse')
        stepElement.classList.add('opacity-50', 'bg-gray-400')
        stepText.classList.remove('opacity-100')
        stepText.classList.add('opacity-50')
      }
    })
  }

  // Méthodes pour déclencher depuis l'extérieur
  start() {
    this.startProcessing()
  }

  stop() {
    this.stopProcessing()
  }
}

