import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="scroll"
export default class extends Controller {
  connect() {
    this.scrollToBottomInstant()

    // Observer to detect new messages added dynamically
    this.observer = new MutationObserver(() => {
      this.scrollToBottomSmooth()
    })

    // We observe all changes in the messages container
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
    // Use requestAnimationFrame to ensure the DOM is updated
    requestAnimationFrame(() => {
      this.element.scroll({
        top: this.element.scrollHeight,
        behavior: "smooth"
      })
    })
  }

  scrollToBottomInstant() {
    // Instant scroll on load
    requestAnimationFrame(() => {
      this.element.scrollTop = this.element.scrollHeight
    })
  }
}
