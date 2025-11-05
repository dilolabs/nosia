import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  updateCount() {
    const checkboxes = this.element.querySelectorAll('input[type="checkbox"]:checked')
    const count = checkboxes.length
    const countElement = document.getElementById('mcp-selected-count')
    if (countElement) {
      countElement.textContent = count
    }
  }
}
