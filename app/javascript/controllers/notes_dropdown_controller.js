import { Controller } from "@hotwired/stimulus"

const EDGE = 8, GAP = 6
const clamp = (value, min, max) => Math.max(min, Math.min(value, max))

export default class extends Controller {
  connect() {
    if (CSS.supports("position-area", "block-end span-all")) return

    this.listeners = new AbortController()
    const { signal } = this.listeners
    this.element.addEventListener("beforetoggle", this.beforeToggle, { signal })
    this.element.addEventListener("toggle", this.position, { signal })
    this.element.addEventListener("turbo:before-morph-attribute", this.preservePosition, { signal })
    window.addEventListener("resize", this.position, { signal })
    window.addEventListener("scroll", this.position, { signal, capture: true })
    this.position()
  }

  disconnect() {
    this.listeners?.abort()
    cancelAnimationFrame(this.openingFrame)
  }

  closeOnFocusLeave(event) {
    if (this.element.matches(":popover-open") && !this.element.contains(event.target) &&
        event.target !== this.element.previousElementSibling) {
      this.element.hidePopover()
    }
  }

  beforeToggle = (event) => {
    if (event.target === this.element && event.newState === "open") {
      cancelAnimationFrame(this.openingFrame)
      this.openingFrame = requestAnimationFrame(this.position)
    }
  }

  preservePosition = (event) => {
    if (event.target === this.element && event.detail.attributeName === "style" &&
        event.detail.mutationType === "remove" && this.open) event.preventDefault()
  }

  position = () => {
    if (!this.open) return

    const { top, bottom, left, width } = this.element.previousElementSibling.getBoundingClientRect()
    const above = top - GAP - EDGE
    const below = innerHeight - bottom - GAP - EDGE
    const placeAbove = above > below
    const style = this.element.style
    style.setProperty("--notes-dropdown-space", `${Math.max(0, placeAbove ? above : below)}px`)
    const panel = this.element.getBoundingClientRect()
    const x = clamp(left + (width - panel.width) / 2, EDGE, innerWidth - panel.width - EDGE)
    const y = clamp(placeAbove ? top - GAP - panel.height : bottom + GAP, EDGE, innerHeight - panel.height - EDGE)
    style.setProperty("--notes-dropdown-inset", `${y}px auto auto ${x}px`)
    style.setProperty("--notes-dropdown-margin", "0")
  }

  get open() {
    return this.element.matches(":popover-open, :modal")
  }
}
