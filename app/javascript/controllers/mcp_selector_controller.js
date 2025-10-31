import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  open(event) {
    event?.preventDefault()
    const modal = document.getElementById("mcp-selector-modal")
    if (modal) {
      modal.classList.remove("hidden")
    }
  }

  close(event) {
    event?.preventDefault()
    this.element.classList.add("hidden")
  }

  // Close on escape key
  connect() {
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape" && !this.element.classList.contains("hidden")) {
      this.close()
    }
  }
}
