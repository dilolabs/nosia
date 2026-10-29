import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "latest"]

  connect() {
    this.state = this.element.chatReaderState ||= { paused: false, anchor: null, pending: false }
    this.onScroll = this.scrolled.bind(this)
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
    return matchMedia("(max-width: 639px), (max-height: 700px)").matches ? this.main : this.viewport
  }

  observeSurface() {
    this.stopObserving()
    this.main = this.element.closest("main")
    this.viewport = this.viewportTarget
    this.main.addEventListener("scroll", this.onScroll)
    this.viewport.addEventListener("scroll", this.onScroll)
    const changed = this.contentChanged()
    this.changed ||= changed
    this.mutations = new MutationObserver(() => this.schedule(this.contentChanged()))
    this.mutations.observe(this.viewport, { childList: true, subtree: true, characterData: true })
    this.resize = new ResizeObserver(() => this.schedule())
    for (const element of [this.main, this.element, this.viewport, this.viewport.firstElementChild]) {
      if (element) this.resize.observe(element)
    }
  }

  stopObserving() {
    this.main?.removeEventListener("scroll", this.onScroll)
    this.viewport?.removeEventListener("scroll", this.onScroll)
    this.mutations?.disconnect()
    this.resize?.disconnect()
  }

  scrolled(event) {
    const surface = this.surface
    const updateTop = this.updatePosition?.surface === surface ? this.updatePosition.top : this.position?.top
    // Layout and our own positioning also dispatch scroll, but do not change intent.
    if (event.target !== surface || (this.frame && this.rendering) || this.position?.surface !== surface || updateTop === surface.scrollTop) return
    // Content growing below the reader can anchor the browser downward, but an
    // upward move is reader intent and must beat the queued follow reconciliation.
    const scrolledBackDuringGrowth = this.updatedMessages.size > 0 && surface.scrollHeight > this.position.height && surface.scrollTop < updateTop
    if (this.position.clientHeight !== surface.clientHeight || (this.position.height !== surface.scrollHeight && !scrolledBackDuringGrowth)) {
      this.schedule()
      return
    }

    this.state.paused = this.gap > 80
    if (!this.state.paused) this.state.pending = false
    if (scrolledBackDuringGrowth) this.changed ||= this.updatedContentBelow()
    this.capture()
    this.reflect()
    this.rememberPosition()
  }

  get gap() {
    return this.surface.scrollHeight - this.surface.clientHeight - this.surface.scrollTop
  }

  capture(event) {
    if (!this.state.paused || (event && this.frame)) return

    const top = this.surface.getBoundingClientRect().top
    const message = [...this.viewport.querySelectorAll(".message-container[id]")].find(element => element.getBoundingClientRect().bottom > top)
    if (message) {
      // A message can span many screens. Its visible block survives streamed replacements
      // and width changes more accurately than the top of the whole message bubble.
      const blocks = [...message.querySelectorAll(".ai-response-content > *")]
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

  contentChanged() {
    const contents = new Map()
    const bottom = this.surface.getBoundingClientRect().bottom
    let changed = false
    let updated = false
    for (const message of this.viewport.querySelectorAll(".message-container[id]")) {
      const content = message.querySelector(".ai-response-content, .n-chat-user-body")
      if (content) {
        const text = content.textContent
        contents.set(message.id, text)
        if (this.contents && this.contents.get(message.id) !== text) {
          // Native anchoring can put new content above the viewport before the
          // reader scrolls back. Keep content changes separate from visibility.
          this.updatedMessages.add(message.id)
          updated = true
          if (content.getBoundingClientRect().bottom > bottom) changed = true
        }
      }
    }
    this.contents = contents
    if (updated) this.updatePosition = { surface: this.surface, top: this.surface.scrollTop }
    return changed
  }

  updatedContentBelow() {
    const bottom = this.surface.getBoundingClientRect().bottom
    return [...this.updatedMessages].some(id => {
      const content = document.getElementById(id)?.querySelector(".ai-response-content, .n-chat-user-body")
      return content && this.viewport.contains(content) && content.getBoundingClientRect().bottom > bottom
    })
  }

  schedule(changed = false) {
    this.changed ||= changed
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.reconcile()
    })
  }

  reconcile() {
    if (!this.element.isConnected || !this.hasViewportTarget) return
    if (this.viewport !== this.viewportTarget) this.observeSurface()

    if (this.state.paused) {
      // Judge visibility at the reader's anchor, not native anchoring's temporary
      // position. The Latest HUD can then reflow the surface without moving it.
      this.restoreAnchor()
      if ((this.changed || this.updatedContentBelow()) && this.gap > 80) this.state.pending = true
      this.reflect()
      this.restoreAnchor()
    } else {
      this.reflect()
      this.surface.scrollTop = this.surface.scrollHeight
    }
    this.changed = false
    this.updatedMessages.clear()
    this.updatePosition = null
    this.rememberPosition()
    this.rendering = false
  }

  restoreAnchor() {
    const anchor = this.state.anchor
    const message = anchor && document.getElementById(anchor.id)
    if (message && this.viewport.contains(message)) {
      const block = message.querySelectorAll(".ai-response-content > *")[anchor.block] || message
      this.surface.scrollTop += block.getBoundingClientRect().top - this.surface.getBoundingClientRect().top - anchor.offset
    }
  }

  rememberPosition() {
    this.position = {
      surface: this.surface, top: this.surface.scrollTop,
      height: this.surface.scrollHeight, clientHeight: this.surface.clientHeight
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
    this.rendering = true
    this.schedule()
  }
}
