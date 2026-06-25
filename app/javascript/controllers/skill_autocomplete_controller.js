import { Controller } from "@hotwired/stimulus"

// Shows a "/" command palette of agent skills above the chat input.
// Opens when the textarea value starts with "/" and the user is still typing
// the skill name (no space yet) — matching the explicit trigger the server
// detector recognises (AgentSkill::Detector). Selecting an item inserts
// "/skill-name " and closes the menu.
export default class extends Controller {
  static targets = [ "input", "menu" ]
  static values = { skills: Array }

  connect() {
    this.open = false
    this.activeIndex = -1
    this.items = []
    this.close()
  }

  onInput() {
    const query = this.currentToken()
    if (query === null) return this.close()

    this.items = this.filter(query)
    if (this.items.length === 0) return this.close()

    this.activeIndex = 0
    this.render()
  }

  keydown(e) {
    if (!this.open) return

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault(); e.stopImmediatePropagation()
        this.move(1)
        break
      case "ArrowUp":
        e.preventDefault(); e.stopImmediatePropagation()
        this.move(-1)
        break
      case "Enter":
      case "Tab":
        e.preventDefault(); e.stopImmediatePropagation()
        this.select(this.activeIndex)
        break
      case "Escape":
        e.preventDefault(); e.stopImmediatePropagation()
        this.close()
        break
    }
  }

  // Returns the partial skill name being typed, or null when the autocomplete
  // should not be active.
  currentToken() {
    const value = this.inputTarget.value
    const match = value.match(/^\/([a-zA-Z0-9_-]*)$/)
    return match ? match[1].toLowerCase() : null
  }

  filter(query) {
    if (query === "") return this.skillsValue
    const starts = [], includes = []
    for (const skill of this.skillsValue) {
      const name = skill.name.toLowerCase()
      if (name.startsWith(query)) starts.push(skill)
      else if (name.includes(query)) includes.push(skill)
    }
    return starts.concat(includes)
  }

  move(delta) {
    const count = this.items.length
    this.activeIndex = (this.activeIndex + delta + count) % count
    this.render()
  }

  select(index) {
    const skill = this.items[index]
    if (!skill) return

    const textarea = this.inputTarget
    textarea.value = `/${skill.name} `
    textarea.focus()
    textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    // Notify the chat-input controller so it can resize the textarea, and so
    // our own onInput re-evaluates (the trailing space closes the menu).
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
    this.close()
  }

  render() {
    const menu = this.menuTarget
    menu.replaceChildren()

    this.items.forEach((skill, index) => {
      const item = document.createElement("div")
      item.className = "n-skill-item"
      if (index === this.activeIndex) item.classList.add("n-skill-item-active")
      item.setAttribute("role", "option")
      item.setAttribute("aria-selected", index === this.activeIndex)

      const name = document.createElement("span")
      name.className = "n-skill-item-name"
      name.textContent = `/${skill.name}`
      item.appendChild(name)

      if (skill.description) {
        const desc = document.createElement("span")
        desc.className = "n-skill-item-desc"
        desc.textContent = skill.description
        item.appendChild(desc)
      }

      // mousedown (not click) so the textarea keeps focus during selection.
      item.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.select(index)
      })

      menu.appendChild(item)
    })

    menu.classList.remove("hidden")
    this.open = true
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.menuTarget.replaceChildren()
    this.open = false
    this.activeIndex = -1
    this.items = []
  }
}
