import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="scroll"
export default class extends Controller {
  connect() {
    this.scrollToBottomInstant()

    // Observer pour détecter les nouveaux messages ajoutés dynamiquement
    this.observer = new MutationObserver(() => {
      this.scrollToBottomSmooth()
    })

    // Observer tous les changements dans le conteneur de messages
    const messagesContainer = this.element.querySelector('[id$="_messages"]')
    if (messagesContainer) {
      this.observer.observe(messagesContainer, {
        childList: true,
        subtree: true
      })
    }
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  scrollToBottom(event) {
    this.scrollToBottomSmooth()
  }

  scrollToBottomSmooth() {
    // Utiliser requestAnimationFrame pour s'assurer que le DOM est mis à jour
    requestAnimationFrame(() => {
      this.element.scroll({
        top: this.element.scrollHeight,
        behavior: "smooth"
      })
    })
  }

  scrollToBottomInstant() {
    // Scroll instantané au chargement
    requestAnimationFrame(() => {
      this.element.scrollTop = this.element.scrollHeight
    })
  }
}
