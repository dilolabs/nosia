import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "trigger"]
  static values = { history: Boolean }
  static outlets = ["chat-dialog"]

  connect() {
    this.caching = false
    this.expanded = this.element.dataset.orbiteHistoryExpanded !== "false"
    this.wide = matchMedia("(min-width: 1280px)")
    this.mobile = matchMedia("(max-width: 767px)")
    this.changed = () => this.layout()
    this.wide.addEventListener("change", this.changed)
    this.mobile.addEventListener("change", this.changed)
    this.layout()
  }

  disconnect() {
    this.wide.removeEventListener("change", this.changed)
    this.mobile.removeEventListener("change", this.changed)
  }

  get desiredMode() {
    return this.historyValue && this.wide.matches ? "inline" : this.mobile.matches ? "mobile" : "modal"
  }

  layout() {
    if (!this.wide || !this.mobile || !this.hasChatDialogOutlet || !this.hasPanelTarget) return

    const mode = this.desiredMode
    if (mode !== this.mode) {
      this.chatDialogOutlet.reconfigure(this.panelTarget, () => {
        this.panelTarget.dataset.inline = String(mode === "inline")
        this.panelTarget.open = mode === "inline" && this.expanded
      }, this.fallback())
      this.mode = mode
    } else if (mode === "inline" && !this.panelTarget.matches(":modal")) this.panelTarget.open = this.expanded
    this.reflect()
  }

  chatDialogOutletConnected() {
    this.layout()
  }

  triggerTargetConnected() {
    if (this.mode) this.reflect()
  }

  toggle(event) {
    event.preventDefault()
    this.caching = false
    if (this.mode === "inline") {
      this.expanded = !this.panelTarget.open
      this.chatDialogOutlet.reconfigure(this.panelTarget, () => { this.panelTarget.open = this.expanded }, this.fallback())
    } else this.chatDialogOutlet.openDialog(this.panelTarget, event.currentTarget)
    this.reflect()
  }

  utilities(event) {
    event.preventDefault()
    this.caching = false
    if (this.mode === "inline") {
      this.expanded = true
      this.panelTarget.open = true
    } else this.chatDialogOutlet.openDialog(this.panelTarget, event.currentTarget)
    this.reflect()
    this.chatDialogOutlet.focus(this.panelTarget.querySelector("#dropdownUser"))
  }

  close(event) {
    event.preventDefault()
    this.chatDialogOutlet.closeDialog(this.panelTarget, this.fallback())
  }

  closed() {
    if (this.caching || this.panelTarget.open) return

    if (this.mode === "inline") this.expanded = false
    this.reflect()
  }

  fallback() {
    return this.triggerTargets.find(element => {
      const box = element.getBoundingClientRect()
      return element.checkVisibility() && box.top >= 0 && box.bottom <= innerHeight
    }) || this.element.querySelector("#workspace-utilities-trigger")
  }

  reflect() {
    this.element.dataset.orbiteNavigationMode = this.mode
    this.element.dataset.orbiteHistoryExpanded = String(this.expanded)
    this.triggerTargets.forEach(button => {
      button.setAttribute("aria-expanded", String(this.panelTarget.open))
      if (this.mode === "inline") button.removeAttribute("aria-haspopup")
      else button.setAttribute("aria-haspopup", "dialog")
    })
  }

  preserve(event) {
    if (event.target === this.panelTarget && ["open", "data-inline"].includes(event.detail.attributeName)) event.preventDefault()
  }

  beforeCache() {
    this.caching = true
    this.element.dataset.orbiteHistoryExpanded = String(this.expanded)
  }
}
