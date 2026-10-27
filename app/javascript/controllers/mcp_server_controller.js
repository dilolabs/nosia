import { Controller } from "@hotwired/stimulus"

// Progressively enhances local, preloaded sections with manually activated tabs.
export default class extends Controller {
  static targets = ["list", "tab", "panel"]

  connect() {
    this.listTarget.setAttribute("role", "tablist")
    this.tabTargets.forEach(tab => { tab.setAttribute("role", "tab"); tab.setAttribute("aria-controls", tab.dataset.tabKey) })
    this.panelTargets.forEach(panel => { panel.setAttribute("role", "tabpanel"); panel.setAttribute("aria-labelledby", `mcp-tab-${panel.dataset.tabKey}`); panel.tabIndex = 0 })
    this.restore()
  }

  disconnect() {
    this.listTarget.removeAttribute("role")
    this.tabTargets.forEach(tab => ["role", "aria-controls", "aria-selected", "tabindex"].forEach(name => tab.removeAttribute(name)))
    this.panelTargets.forEach(panel => { panel.hidden = false; ["role", "aria-labelledby", "tabindex"].forEach(name => panel.removeAttribute(name)) })
  }

  restore() {
    const candidate = location.hash.slice(1)
    this.activate(this.tabTargets.some(tab => tab.dataset.tabKey === candidate) ? candidate : "overview")
  }

  select(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    const key = event.currentTarget.dataset.tabKey
    this.activate(key)
    history.pushState(null, "", `#${key}`)
  }

  key(event) {
    const index = this.tabTargets.indexOf(event.currentTarget)
    let next
    if (event.key === "ArrowLeft") next = (index - 1 + this.tabTargets.length) % this.tabTargets.length
    if (event.key === "ArrowRight") next = (index + 1) % this.tabTargets.length
    if (event.key === "Home") next = 0
    if (event.key === "End") next = this.tabTargets.length - 1
    if (next !== undefined) {
      event.preventDefault()
      this.tabTargets.forEach((tab, i) => tab.tabIndex = i === next ? 0 : -1)
      this.tabTargets[next].focus()
    } else if (event.key === " " || event.key === "Enter") {
      event.preventDefault()
      const key = event.currentTarget.dataset.tabKey
      this.activate(key)
      history.pushState(null, "", `#${key}`)
    }
  }

  resetRoving() {
    queueMicrotask(() => {
      if (this.hasListTarget && !this.listTarget.contains(document.activeElement)) this.tabTargets.forEach(tab => tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1)
    })
  }

  activate(key) {
    this.tabTargets.forEach(tab => { const selected = tab.dataset.tabKey === key; tab.setAttribute("aria-selected", String(selected)); tab.tabIndex = selected ? 0 : -1 })
    this.panelTargets.forEach(panel => panel.hidden = panel.dataset.tabKey !== key)
  }
}
