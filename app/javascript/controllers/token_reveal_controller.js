import Clipboard from "@stimulus-components/clipboard"

export default class extends Clipboard {
  static targets = ["status"]
  static values = { copying: String, failure: String }

  initialize() {
    this.generation = 0
  }

  connect() {
    if (this.originalContent === undefined) {
      super.connect()
    }

    this.buttonTarget.innerHTML = this.originalContent
    this.buttonTarget.setAttribute("aria-disabled", "false")
    this.statusTarget.textContent = ""
    this.element.focus()
  }

  disconnect() {
    this.generation++
  }

  async copy(event) {
    event.preventDefault()
    if (this.buttonTarget.getAttribute("aria-disabled") === "true") return

    const generation = this.generation
    this.buttonTarget.setAttribute("aria-disabled", "true")
    this.buttonTarget.textContent = this.copyingValue
    this.statusTarget.textContent = ""
    let message

    try {
      if (!navigator.clipboard?.writeText) throw new Error("unavailable")

      await navigator.clipboard.writeText(this.sourceTarget.value)
      message = this.successContentValue
    } catch {
      message = this.failureValue
    } finally {
      if (this.element.isConnected && this.generation === generation) {
        this.statusTarget.textContent = message
        this.buttonTarget.innerHTML = this.originalContent
        this.buttonTarget.setAttribute("aria-disabled", "false")
      }
    }
  }

  clear() {
    this.generation++
    this.sourceTarget.value = ""
    this.sourceTarget.removeAttribute("value")
    this.element.remove()
  }
}
