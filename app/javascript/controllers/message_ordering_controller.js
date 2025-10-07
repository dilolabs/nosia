import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]

  connect() {
    this.reorderMessages()
    this.observeNewMessages()
  }

  observeNewMessages() {
    // Watch for new messages being added to the DOM
    const observer = new MutationObserver((mutations) => {
      let shouldReorder = false

      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === 1 && node.matches('[data-message-ordering-target="message"]')) {
            shouldReorder = true
          }
        })
      })

      if (shouldReorder) {
        // Small delay to ensure all attributes are set
        setTimeout(() => this.reorderMessages(), 10)
      }
    })

    observer.observe(this.element, { childList: true, subtree: true })
    this.observer = observer
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  reorderMessages() {
    const messages = Array.from(this.messageTargets)

    // Sort by timestamp (created_at)
    messages.sort((a, b) => {
      const timeA = new Date(a.dataset.createdAt).getTime()
      const timeB = new Date(b.dataset.createdAt).getTime()
      return timeA - timeB
    })

    // Reorder in DOM
    messages.forEach((message) => {
      this.element.appendChild(message)
    })
  }
}

