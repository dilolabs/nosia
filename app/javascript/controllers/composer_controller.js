import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

// Replaces chat_input_controller + skill_autocomplete_controller for the Lexxy
// editor. Enter-to-send, URL→Website interception, PDF→Document interception,
// accumulation of attached source ids into hidden form fields, and the /skill
// command palette.
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
  static targets = ["editor", "websiteIds", "documentIds", "menu"]
  static values = { skills: Array }

  connect() {
    this.boundInsertLink = this.onInsertLink.bind(this)
    this.boundUploadEnd = this.onUploadEnd.bind(this)
    this.boundHandleKeys = this.handleKeys.bind(this)
    this.boundChange = this.onChange.bind(this)
    this.sentSgids = new Set()
    this.paletteOpen = false
    this.activeIndex = -1
    this.items = []

    this.editorTarget.addEventListener("lexxy:insert-link", this.boundInsertLink)
    this.editorTarget.addEventListener("lexxy:upload-end", this.boundUploadEnd)
    this.editorTarget.addEventListener("lexxy:change", this.boundChange)
    this.editorTarget.addEventListener("keydown", this.boundHandleKeys)
    this.closePalette()
  }

  disconnect() {
    this.closePalette()
    this.editorTarget.removeEventListener("lexxy:insert-link", this.boundInsertLink)
    this.editorTarget.removeEventListener("lexxy:upload-end", this.boundUploadEnd)
    this.editorTarget.removeEventListener("lexxy:change", this.boundChange)
    this.editorTarget.removeEventListener("keydown", this.boundHandleKeys)
  }

  // Enter sends; Shift/Meta/Ctrl+Enter fall through. When the /skill palette is
  // open, arrows/Enter/Tab/Escape drive the palette instead (and swallow the
  // key so Enter doesn't also send). The controller may be attached to the
  // <form> or to a wrapper div inside it, so resolve the form before submitting.
  handleKeys(event) {
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

  // Lexxy dispatches lexxy:insert-link on the editor with detail.url when a URL
  // is pasted/linked. Record a Website for it; Lexxy keeps its own <a href>.
  async onInsertLink(event) {
    const url = event.detail.url
    if (!url) return

    const response = await post("/chat_sources", {
      body: JSON.stringify({ url }),
      headers: { "Content-Type": "application/json", "Accept": "application/json" }
    })
    if (response.ok) {
      const data = await response.json
      this.addId(this.websiteIdsTarget, data.id)
    }
  }

  // Lexxy dispatches lexxy:upload-end with { file, error } — the blob's
  // attachable sgid is NOT in the event. It lands on the embedded
  // <action-text-attachment sgid="..."> node a tick later, once editor.update()
  // commits the replacement. Poll for an unregistered sgid, then record a
  // Document for it. (One PDF per paste is the common case; the sentSgids guard
  // keeps us from double-registering on re-fire.)
  async onUploadEnd(event) {
    if (event.detail.error) return

    const sgid = await this.nextUnsentAttachmentSgid()
    if (!sgid) return
    this.sentSgids.add(sgid)

    const response = await post("/chat_sources", {
      body: JSON.stringify({ attachable_sgid: sgid }),
      headers: { "Content-Type": "application/json", "Accept": "application/json" }
    })
    if (response.ok) {
      const data = await response.json
      this.addId(this.documentIdsTarget, data.id)
    }
  }

  nextUnsentAttachmentSgid() {
    return new Promise(resolve => {
      let attempts = 0
      const check = () => {
        const nodes = this.editorTarget.querySelectorAll("action-text-attachment")
        for (const node of nodes) {
          const sgid = node.getAttribute("sgid")
          if (sgid && !this.sentSgids.has(sgid)) return resolve(sgid)
        }
        if (++attempts > 20) {
          console.warn("[composer] lexxy:upload-end fired but no action-text-attachment sgid appeared in time; PDF not registered.")
          return resolve(null)
        }
        requestAnimationFrame(check)
      }
      check()
    })
  }

  // Clone the target hidden input's name so ids submit in the right params
  // namespace (chat[attached_website_ids][] vs message[attached_website_ids][]).
  addId(target, id) {
    if (!id) return
    if (!target.name) {
      console.warn("[composer] hidden id target has no name attribute; attachment not submitted.")
      return
    }
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = target.name
    input.value = id
    target.parentNode.appendChild(input)
  }

  // --- /skill command palette (ported from skill_autocomplete_controller) ---
  // Opens when the editor's plain text is exactly "/<partial>" (no space yet) —
  // the trigger AgentSkill::Detector recognises server-side. Selecting an item
  // replaces the content with "/skill-name " and closes the menu.
  onChange() {
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
