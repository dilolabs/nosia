import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  save(event) {
    const checkbox = event.target
    const form = checkbox.form
    const focused = document.activeElement === checkbox
    checkbox.disabled = true
    form.addEventListener("turbo:submit-end", ({ detail }) => {
      checkbox.disabled = false
      if (!detail.success) checkbox.checked = !checkbox.checked
      if (focused && document.activeElement === document.body) checkbox.focus({ preventScroll: true })
    }, { once: true })
    form.requestSubmit()
  }

  updateCount() {
    const checkboxes = this.element.querySelectorAll('input[type="checkbox"]:checked')
    const count = checkboxes.length
    const countElement = document.getElementById('mcp-selected-count')
    if (countElement) {
      countElement.textContent = count
    }
  }
}
