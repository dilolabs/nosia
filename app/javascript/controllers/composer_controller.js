import { Controller } from "@hotwired/stimulus"

// Replaces chat_input_controller + skill_autocomplete_controller for the Lexxy
// editor. Enter-to-send and the /skill command palette. Source registration is
// handled separately by composer-sources.
//
// CAVEAT (Task 13, highest-risk): the palette reads the editor's plain text via
// the element's `value` getter and inserts via `value=` — the plan-sanctioned
// fallback when the Lexical selection API isn't reachable cleanly. This was NOT
// browser-verified (no browser in this environment); Task 14/16 must confirm:
//   1. `lexxy:change` fires on each keystroke and `value` reads fresh (the gem
//      clears cachedValue on update), so the /^\/(...) $/ detection is live.
//   2. Lexxy ships a built-in prompt-menu/mentions popover that may also react
//      to `/`. If it conflicts, either disable it or hook the skill list into
//      it instead of this standalone menu.
//   3. `value=` replacing the whole document is acceptable for the
//      "content is just /partial" case (matches the old textarea behavior).
export default class extends Controller {
  static targets = ["editor", "menu"]
  static values = { skills: Array }

  connect() {
    this.boundHandleKeys = this.handleKeys.bind(this)
    this.boundChange = this.onChange.bind(this)
    this.boundSubmitStart = this.submitStart.bind(this)
    this.paletteOpen = false
    this.activeIndex = -1
    this.items = []
    this.contentStyled = false

    this.styleContent()
    this.editorTarget.addEventListener("lexxy:change", this.boundChange)
    this.editorTarget.addEventListener("keydown", this.boundHandleKeys)
    this.form = this.element.tagName === "FORM" ? this.element : this.element.closest("form")
    if (this.form) this.form.addEventListener("turbo:submit-start", this.boundSubmitStart)
    this.closePalette()
  }

  disconnect() {
    this.closePalette()
    this.editorTarget.removeEventListener("lexxy:change", this.boundChange)
    this.editorTarget.removeEventListener("keydown", this.boundHandleKeys)
    if (this.form) this.form.removeEventListener("turbo:submit-start", this.boundSubmitStart)
  }

  // Lexxy builds the contenteditable as <div class="lexxy-editor__content"> and
  // scopes ALL content typography (heading sizes, list markers, blockquote,
  // table borders, s/u/mark, code, links) to :where(.lexxy-content) in
  // lexxy-content.css. That class is meant for *rendered* output, so the editor
  // never gets it -- and with Tailwind Preflight stripping UA defaults (plus
  // the app's swapped ul/ol rules), the editable area is left unstyled. Add the
  // class once the content div exists so the engine's own content styles apply.
  // Idempotent: runs from connect() and onChange() (the latter covers the case
  // where the <lexxy-editor> custom element upgrades after Stimulus connects).
  styleContent() {
    if (this.contentStyled) return
    const content = this.editorTarget.querySelector(".lexxy-editor__content")
    if (content) {
      content.classList.add("lexxy-content")
      this.contentStyled = true
    }
  }

  // turbo:submit-start fires on the <form> the instant the user submits. Lock the
  // composer in the same frame — before the server's Turbo Stream response arrives —
  // so the user sees immediate feedback that the send registered. The server then
  // re-renders the form with generating=true (busy), and finish_generation! clears it.
  submitStart() {
    if (this.editorTarget) this.editorTarget.disabled = true
    const btn = this.element.querySelector("button[type='submit']")
    if (btn) btn.disabled = true
  }

  // Enter sends; Shift/Meta/Ctrl+Enter fall through. When the /skill palette is
  // open, arrows/Enter/Tab/Escape drive the palette instead (and swallow the
  // key so Enter doesn't also send). The controller may be attached to the
  // <form> or to a wrapper div inside it, so resolve the form before submitting.
  handleKeys(event) {
    const content = event.target.closest(".lexxy-editor__content")
    if (!content || !this.editorTarget.contains(content)) return

    if (this.paletteOpen) {
      if (event.key === "ArrowDown") { event.preventDefault(); event.stopImmediatePropagation(); this.movePalette(1); return }
      if (event.key === "ArrowUp") { event.preventDefault(); event.stopImmediatePropagation(); this.movePalette(-1); return }
      if (event.key === "Enter" || event.key === "Tab") { event.preventDefault(); event.stopImmediatePropagation(); this.selectPalette(this.activeIndex); return }
      if (event.key === "Escape") { event.preventDefault(); event.stopImmediatePropagation(); this.closePalette(); return }
    }

    if (event.key === "Enter" && !event.shiftKey && !event.metaKey && !event.ctrlKey) {
      event.preventDefault()
      const form = this.element.tagName === "FORM" ? this.element : this.element.closest("form")
      if (form) form.requestSubmit()
    }
  }

  // --- /skill command palette (ported from skill_autocomplete_controller) ---
  // Opens when the editor's plain text is exactly "/<partial>" (no space yet) —
  // the trigger AgentSkill::Detector recognises server-side. Selecting an item
  // replaces the content with "/skill-name " and closes the menu.
  onChange() {
    this.styleContent()
    const token = this.currentToken()
    if (token === null) return this.closePalette()

    this.items = this.filterSkills(token)
    if (this.items.length === 0) return this.closePalette()

    this.activeIndex = 0
    this.renderPalette()
  }

  currentToken() {
    const text = this.editorPlainText()
    const match = text.match(/^\/([a-zA-Z0-9_-]*)$/)
    return match ? match[1].toLowerCase() : null
  }

  editorPlainText() {
    const html = this.editorTarget.value || ""
    const tmp = document.createElement("div")
    tmp.innerHTML = html
    return (tmp.textContent || "").trim()
  }

  filterSkills(query) {
    if (query === "") return this.skillsValue
    const starts = [], includes = []
    for (const skill of this.skillsValue) {
      const name = skill.name.toLowerCase()
      if (name.startsWith(query)) starts.push(skill)
      else if (name.includes(query)) includes.push(skill)
    }
    return starts.concat(includes)
  }

  movePalette(delta) {
    const count = this.items.length
    this.activeIndex = (this.activeIndex + delta + count) % count
    this.renderPalette()
  }

  selectPalette(index) {
    const skill = this.items[index]
    if (!skill) return
    // Skill names are server-constrained to [a-zA-Z0-9_-]+ (the charset
    // currentToken matches). Assert it before interpolating into HTML — unlike
    // the old textarea, we now feed an HTML string to the editor.
    if (!/^[a-zA-Z0-9_-]+$/.test(skill.name)) return

    // Replace the "/partial" content with the resolved command. The palette is
    // only open when content is exactly "/partial", so a full replace matches
    // the old textarea behavior (set value to "/skill-name "). Lexxy's set
    // value runs a discrete editor.update that fires lexxy:change, so onChange
    // re-evaluates against the new text and the palette stays closed; the
    // explicit closePalette() below is the safety net if that firing is
    // delayed. (Verify in Task 14/16.)
    this.editorTarget.value = `<p>/${skill.name} </p>`
    this.closePalette()
    this.editorTarget.focus()
  }

  renderPalette() {
    if (!this.hasMenuTarget) return
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

      // mousedown (not click) so the editor keeps focus during selection.
      item.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.selectPalette(index)
      })

      menu.appendChild(item)
    })

    menu.classList.remove("hidden")
    this.paletteOpen = true
  }

  closePalette() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
    this.menuTarget.replaceChildren()
    this.paletteOpen = false
    this.activeIndex = -1
    this.items = []
  }
}
