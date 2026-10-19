import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "formatting"]

  get locked() {
    return this.editorTarget.inert || this.editorTarget.hasAttribute("disabled") || Boolean(this.element.closest("[inert]"))
  }

  get toolbar() {
    return this.editorTarget.toolbarElement
  }

  upload() {
    if (this.locked) return

    this.toolbar?.querySelector("button[data-command='uploadFile']")?.click()
  }

  syncFormatting() {
    if (this.locked) this.formattingTarget.open = false

    this.element.toggleAttribute("data-formatting-open", this.formattingTarget.open)
    if (this.formattingTarget.open) {
      this.toolbar?.requestOverflowRefresh()
    } else {
      this.toolbar?.closeDropdowns({})
    }
    this.positionTools()
  }

  formattingKey(event) {
    event.preventDefault()
    if (this.locked) return

    this.formattingTarget.open = !this.formattingTarget.open
    this.syncFormatting()
    if (this.formattingTarget.open) {
      requestAnimationFrame(() => {
        if (!this.element.isConnected || !this.formattingTarget.open || this.locked) return

        const button = [...(this.toolbar?.querySelectorAll("button") || [])].find(item => !item.disabled && item.getClientRects().length)
        button?.focus()
      })
    }
  }

  linkShortcut(event) {
    if (event.key.toLowerCase() !== "k" || !(event.ctrlKey || event.metaKey) || this.locked) return
    if (!this.editorTarget.contains(event.target)) return

    event.preventDefault()
    event.stopPropagation()
    this.formattingTarget.open = true
    this.syncFormatting()
    this.toolbar?.querySelector("button[name='link']")?.click()
  }

  toolsToggled(event) {
    event.currentTarget.querySelector(".n-composer-tools-panel").style.visibility = "hidden"
    if (event.currentTarget.open) {
      this.formattingTarget.open = false
      this.syncFormatting()
    }
  }

  positionTools() {
    const tools = this.element.querySelector("[data-composer-tools][open]")
    if (!tools) return

    const panel = tools.querySelector(".n-composer-tools-panel")
    const trigger = tools.querySelector("summary").getBoundingClientRect()
    const row = tools.closest(".n-composer-actions").getBoundingClientRect()
    const minimum = Math.max(row.left + 12, 12)
    const maximum = Math.min(row.right - 12, window.innerWidth - 12) - panel.getBoundingClientRect().width
    const left = Math.min(Math.max(trigger.left, minimum), maximum)

    panel.style.left = `${left - row.left}px`
    panel.style.bottom = `${row.bottom - trigger.top + 8}px`
    panel.style.visibility = "visible"
  }

  escape(event) {
    const tools = this.element.querySelector("[data-composer-tools][open]")
    if (tools) {
      event.preventDefault()
      tools.open = false
      tools.querySelector("summary")?.focus()
    } else if (this.formattingTarget.open) {
      event.preventDefault()
      this.formattingTarget.open = false
      this.syncFormatting()
      this.formattingTarget.querySelector("summary")?.focus()
    }
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.closeDisclosures()
  }

  reset(event) {
    if (event.detail?.root && !event.detail.root.contains(this.element)) return

    this.closeDisclosures()
  }

  closeDisclosures() {
    this.formattingTarget.open = false
    const tools = this.element.querySelector("[data-composer-tools]")
    if (tools) tools.open = false
    this.syncFormatting()
  }
}
