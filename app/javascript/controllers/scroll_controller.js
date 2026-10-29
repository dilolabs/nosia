import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "latest"]

  connect() {
    this.state = this.element.chatReaderState ||= { paused: false, anchor: null, pending: false }
    this.onScroll = this.scrolled.bind(this)
    this.onKeydown = event => {
      this.navigation = event.isTrusted && event.key === "Tab" ? { event, top: this.surface.scrollTop } : null
    }
    this.onKeyup = () => { this.navigation = null }
    this.onFocus = this.focused.bind(this)
    this.onFocusOut = event => {
      if (!this.main.contains(event.relatedTarget)) this.navigation = null
    }
    this.onDisclosureClick = this.disclosureClicked.bind(this)
    this.submissions = new Map()
    this.updatedMessages = new Set()
    this.observeSurface()
    this.schedule()
  }

  disconnect() {
    this.stopObserving()
    cancelAnimationFrame(this.frame)
    this.frame = null
    for (const [form, listener] of this.submissions) form.removeEventListener("turbo:submit-end", listener)
    this.submissions.clear()
  }

  get surface() {
    return this.main
  }

  observeSurface() {
    this.stopObserving()
    // The application scrolls; the transcript remains the observed reading content.
    this.main = this.element.closest("[data-application-scroll]")
    this.viewport = this.viewportTarget
    this.main.addEventListener("scroll", this.onScroll)
    this.main.addEventListener("keydown", this.onKeydown)
    this.main.addEventListener("keyup", this.onKeyup)
    this.main.addEventListener("focusin", this.onFocus)
    this.main.addEventListener("focusout", this.onFocusOut)
    this.main.addEventListener("click", this.onDisclosureClick)
    this.contentChanged()
    this.rememberPosition()
    this.mutations = new MutationObserver(records => {
      this.contentChanged(this.mutationMessageIds(records))
      this.rememberPosition()
      this.schedule()
    })
    this.mutations.observe(this.viewport, { childList: true, subtree: true, characterData: true })
    this.resize = new ResizeObserver(() => {
      this.rememberPosition()
      this.schedule()
    })
    for (const element of [this.main, this.element, this.viewport, this.viewport.firstElementChild]) {
      if (element) this.resize.observe(element)
    }
  }

  stopObserving() {
    this.main?.removeEventListener("scroll", this.onScroll)
    this.main?.removeEventListener("keydown", this.onKeydown)
    this.main?.removeEventListener("keyup", this.onKeyup)
    this.main?.removeEventListener("focusin", this.onFocus)
    this.main?.removeEventListener("focusout", this.onFocusOut)
    this.main?.removeEventListener("click", this.onDisclosureClick)
    this.navigation = null
    this.disclosureActivation = null
    this.mutations?.disconnect()
    this.resize?.disconnect()
  }

  scrolled(event) {
    const surface = this.surface
    if (event.target !== surface) return

    // Observed DOM/layout changes and our own writes record their resulting
    // position. A different position in that same geometry belongs to the reader.
    if (this.position?.surface !== surface || this.position.height !== surface.scrollHeight ||
        this.position.clientHeight !== surface.clientHeight || this.position.clientWidth !== surface.clientWidth) {
      this.rememberPosition()
      this.schedule()
      return
    }
    if (this.position.top === surface.scrollTop) return

    this.recordInput()
  }

  focused() {
    const navigation = this.navigation
    this.navigation = null
    // A native Tab scroll is input even while resize acknowledgment is pending.
    // Existing focus and preventScroll restoration alone never override the anchor.
    if (navigation && !navigation.event.defaultPrevented && navigation.top !== this.surface.scrollTop) this.recordInput()
  }

  disclosureClicked(event) {
    const summary = event.target.closest(".n-chat-header details > summary")
    if (!event.isTrusted || event.defaultPrevented || !summary || !this.element.contains(summary)) return

    this.disclosureActivation = { event, summary, surface: this.surface, open: summary.parentElement.open,
      offset: summary.getBoundingClientRect().top - this.surface.getBoundingClientRect().top }
    this.schedule()
  }

  restoreDisclosure() {
    const activation = this.disclosureActivation
    this.disclosureActivation = null
    if (!activation || activation.event.defaultPrevented || activation.surface !== this.surface ||
        !this.element.contains(activation.summary) || activation.summary.parentElement.open === activation.open) return false

    this.surface.scrollTop += activation.summary.getBoundingClientRect().top - this.surface.getBoundingClientRect().top - activation.offset
    this.recordInput()
    return true
  }

  recordInput() {
    this.state.paused = this.gap > 80
    if (!this.state.paused) this.state.pending = false
    this.capture()
    this.reflect()
    this.rememberPosition()
  }

  get gap() {
    return this.surface.scrollHeight - this.surface.clientHeight - this.surface.scrollTop
  }

  contentFor(message) {
    return message?.querySelector(".ai-response-content, .n-chat-user-body")
  }

  blocksFor(message) {
    return [...(this.contentFor(message)?.children || [])]
  }

  capture(event) {
    if (!this.state.paused || (event && this.frame)) return

    const top = this.surface.getBoundingClientRect().top
    const message = [...this.viewport.querySelectorAll(".message-container[id]")].find(element => element.getBoundingClientRect().bottom > top)
    if (message) {
      // A message can span many screens. Its visible block survives streamed replacements
      // and width changes more accurately than the top of the whole message bubble.
      const blocks = this.blocksFor(message)
      const block = blocks.find(element => element.getBoundingClientRect().bottom > top)
      this.state.anchor = {
        id: message.id, block: blocks.indexOf(block),
        offset: (block || message).getBoundingClientRect().top - top
      }
    }
  }

  beforeStream(event) {
    const target = document.getElementById(event.target.getAttribute("target"))
    if (target && this.viewport.contains(target)) this.capture(event)
  }

  mutationMessageIds(records) {
    const ids = new Set()
    for (const record of records) {
      const target = record.target.nodeType === Node.ELEMENT_NODE ? record.target : record.target.parentElement
      const message = target?.closest(".message-container[id]")
      if (message) ids.add(message.id)
      for (const node of [...record.addedNodes, ...record.removedNodes]) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue
        if (node.matches(".message-container[id]")) ids.add(node.id)
        for (const nested of node.querySelectorAll(".message-container[id]")) ids.add(nested.id)
      }
    }
    return ids
  }

  contentChanged(ids) {
    const previous = this.contents
    this.contents ||= new Map()
    if (!ids) {
      ids = new Set(this.contents.keys())
      for (const message of this.viewport.querySelectorAll(".message-container[id]")) ids.add(message.id)
    }
    for (const id of ids) {
      const message = document.getElementById(id)
      const content = message && this.viewport.contains(message) ? this.contentFor(message) : null
      if (content) {
        const text = content.textContent
        if (previous && previous.get(id) !== text) this.updatedMessages.add(id)
        this.contents.set(id, text)
      } else {
        this.contents.delete(id)
      }
    }
  }

  updatedContentBelow() {
    const bottom = this.surface.getBoundingClientRect().bottom
    return [...this.updatedMessages].some(id => {
      const content = this.contentFor(document.getElementById(id))
      return content && this.viewport.contains(content) && content.getBoundingClientRect().bottom > bottom
    })
  }

  schedule() {
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.reconcile()
    })
  }

  reconcile() {
    if (!this.element.isConnected || !this.hasViewportTarget) return
    if (this.viewport !== this.viewportTarget || this.main !== this.element.closest("[data-application-scroll]")) this.observeSurface()

    if (this.restoreDisclosure()) {
      // A trusted native disclosure owns this one layout change, not later resizes.
      if (this.updatedContentBelow() && this.gap > 80) this.state.pending = true
      this.reflect()
    } else if (this.state.paused) {
      // Judge visibility at the reader's anchor, not native anchoring's temporary
      // position. The Latest HUD can then reflow the surface without moving it.
      this.restoreAnchor()
      if (this.updatedContentBelow() && this.gap > 80) this.state.pending = true
      this.reflect()
      this.restoreAnchor()
    } else {
      this.reflect()
      this.surface.scrollTop = this.surface.scrollHeight
    }
    this.updatedMessages.clear()
    this.rememberPosition()
  }

  restoreAnchor() {
    const anchor = this.state.anchor
    const message = anchor && document.getElementById(anchor.id)
    if (message && this.viewport.contains(message)) {
      const block = this.blocksFor(message)[anchor.block] || message
      this.surface.scrollTop += block.getBoundingClientRect().top - this.surface.getBoundingClientRect().top - anchor.offset
    }
  }

  rememberPosition() {
    this.position = {
      surface: this.surface, top: this.surface.scrollTop,
      height: this.surface.scrollHeight, clientHeight: this.surface.clientHeight, clientWidth: this.surface.clientWidth
    }
  }

  reflect() {
    this.element.dataset.readerFollowing = String(!this.state.paused)
    this.latestTarget.hidden = !(this.state.paused && this.state.pending)
  }

  latest() {
    this.state.paused = false
    this.state.pending = false
    this.state.anchor = null
    this.schedule()
  }

  submissionStarted(event) {
    const form = event.target
    if (!form.matches("form[data-chat-followup]") || this.submissions.has(form)) return

    // The response replaces the form before submit-end, so listen on that form,
    // not just its still-connected workspace ancestor.
    const listener = result => {
      this.submissions.delete(form)
      if (result.detail.success && this.element.isConnected) this.latest()
    }
    this.submissions.set(form, listener)
    form.addEventListener("turbo:submit-end", listener, { once: true })
  }

  afterRender() {
    this.rememberPosition()
    this.schedule()
    // Lexxy commits native focus/caret positioning in a microtask after initialize.
    // Measure that owned work without blocking reader events before the next RAF.
    queueMicrotask(() => {
      if (this.frame && this.element.isConnected) this.rememberPosition()
    })
  }
}
