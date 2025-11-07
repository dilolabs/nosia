import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "counter", "textarea" ]

  connect() {
    this.autogrow()
  }

  autogrow() {
    const textarea = this.textareaTarget
    textarea.style.height = "auto"
    textarea.style.overflow = "hidden"
    textarea.style.height = textarea.scrollHeight + "px"
    if (this.hasCounterTarget) this.counterTarget.textContent = `${textarea.value.length} / 3000`
  }

  handleKeys(e) {
    if (e.key !== "Enter") return
    if (e.shiftKey) { // Shift+Enter = new line
      return // leave the native behavior
    }
    e.preventDefault() // Enter alone = send
    this.element.requestSubmit()
  }

  submit() {}
}
