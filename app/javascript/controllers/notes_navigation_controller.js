import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inline", "sidebar", "dialog", "trigger"]

  connect() {
    if (typeof this.dialogTarget.showModal !== "function") return

    this.medium = window.matchMedia("(48rem <= width < 64rem)")
    this.sync = () => {
      if (!this.medium.matches) this.close()
      if (this.medium.matches) this.triggerTarget.setAttribute("aria-haspopup", "dialog")
      else this.triggerTarget.removeAttribute("aria-haspopup")
    }
    this.medium.addEventListener("change", this.sync)
    this.sync()
  }

  disconnect() {
    this.medium?.removeEventListener("change", this.sync)
  }

  open(event) {
    if (!this.medium?.matches || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    event.preventDefault()
    this.dialogTarget.append(this.sidebarTarget)
    this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  closed() {
    if (this.inlineTarget.contains(this.sidebarTarget)) return

    this.inlineTarget.append(this.sidebarTarget)
    const fallback = this.sidebarTarget.querySelector("[aria-current]") || this.sidebarTarget.querySelector("a")
    const target = this.triggerTarget.getClientRects().length ? this.triggerTarget : fallback
    target?.focus({ preventScroll: true })
  }

  beforeCache() {
    this.close()
    this.inlineTarget.append(this.sidebarTarget)
  }
}
