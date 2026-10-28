import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  clear() {
    this.element.querySelectorAll("[data-mcp-secret]").forEach(input => {
      input.value = ""
      input.defaultValue = ""
    })
  }
}
