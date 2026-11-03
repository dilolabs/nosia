import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["home", "menu", "trigger"]
  static outlets = ["chat-dialog"]

  connect() {
    this.observer = new MutationObserver(() => this.checkOpener())
    this.observer.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["open"] })
    this.reflect(false)
  }

  disconnect() {
    this.observer.disconnect()
    this.close(false)
  }

  triggerTargetConnected(trigger) {
    trigger.popoverTargetElement = this.menuTarget
    trigger.setAttribute("aria-expanded", String(this.open && trigger.id === this.opener?.id))
  }

  get open() {
    return this.hasMenuTarget && this.menuTarget.matches(":popover-open")
  }

  toggle(event) {
    event.preventDefault()
    const opener = event.currentTarget
    if (this.open && this.opener?.id === opener.id) this.close(true)
    else {
      this.close(false)
      this.opener = opener
      this.openerId = opener.id
      const modal = opener.closest("dialog:modal")
      ;(modal || this.homeTarget).append(this.menuTarget)
      this.menuTarget.querySelector("ul").setAttribute("aria-labelledby", opener.id)
      this.menuTarget.showPopover({ source: opener })
      this.position()
      this.reflect(true)
      if (this.open) this.menuTarget.querySelector("a").focus({ preventScroll: true })
    }
  }

  position() {
    if (!this.open || !this.currentOpener()) return

    const box = this.opener.getBoundingClientRect(), gap = 8
    this.menuTarget.style.maxHeight = `${Math.max(0, box.top - gap * 2)}px`
    const menu = this.menuTarget.getBoundingClientRect()
    this.menuTarget.style.left = `${Math.max(gap, Math.min(box.left, innerWidth - menu.width - gap))}px`
    this.menuTarget.style.top = `${Math.max(gap, box.top - menu.height - gap)}px`
  }

  currentOpener() {
    if (!this.opener?.isConnected && this.openerId) this.opener = document.getElementById(this.openerId)
    return this.hasChatDialogOutlet && this.chatDialogOutlet.focusable(this.opener) ? this.opener : null
  }

  checkOpener() {
    if (!this.open) return

    const opener = this.currentOpener(), modal = this.element.querySelector("dialog:modal")
    if (!opener || (modal && !modal.contains(this.menuTarget)) ||
        (this.menuTarget.closest("dialog") && !this.menuTarget.closest("dialog").matches(":modal"))) this.close(true)
    else {
      this.reflect(true)
      this.position()
    }
  }

  beforeToggle(event) {
    if (event.newState === "closed") this.restoreAfterHide = this.menuTarget.contains(document.activeElement)
  }

  toggled() {
    if (!this.open && this.openerId) this.finish(this.restoreAfterHide)
  }

  close(restore = true) {
    if (!this.hasMenuTarget) return

    const inside = this.menuTarget.contains(document.activeElement)
    if (this.open) this.menuTarget.hidePopover()
    this.finish(restore && inside)
  }

  finish(restore) {
    const opener = this.currentOpener()
    this.reflect(false)
    if (restore && this.hasChatDialogOutlet) {
      const fallback = [this.element.querySelector("#workspace-history-rail-trigger"),
        this.element.querySelector("[data-orbite-composer-navigation]"),
        this.element.querySelector("#workspace-mobile-trigger"), this.element]
        .find(element => this.chatDialogOutlet.focusable(element))
      ;(opener || fallback)?.focus({ preventScroll: true })
    }
    if (this.hasHomeTarget && this.menuTarget.parentElement !== this.homeTarget) this.homeTarget.append(this.menuTarget)
    this.opener = null
    this.openerId = null
    this.restoreAfterHide = false
  }

  reflect(open) {
    this.triggerTargets.forEach(trigger => trigger.setAttribute("aria-expanded", String(open && trigger.id === this.openerId)))
  }

  layout() {
    this.close(true)
  }

  scrolled(event) {
    if (this.open && !this.menuTarget.contains(event.target)) this.close(true)
  }

  panelClosed(event) {
    if (event.target.contains(this.menuTarget)) this.close(false)
  }

  beforeVisit(event) {
    if (!event.defaultPrevented) this.close(false)
  }

  beforeCache() {
    this.close(false)
  }
}
