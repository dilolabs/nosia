import { Turbo } from "@hotwired/turbo-rails"

// Owns the Turbo handoff for one mounted Notes editor. A candidate only
// becomes a departure when Turbo actually starts it; consent covers one edit serial.
export default class NoteDeparture {
  constructor(form, { draftSerial, confirmDiscard, onFailure, onReturn }) {
    Object.assign(this, { form, draftSerial, confirmDiscard, onFailure, onReturn })
    this.entry = window.history.state?.turbo
    this.listeners = new AbortController()
    const { signal } = this.listeners
    const actions = {
      "turbo:before-visit": this.#beforeVisit,
      "turbo:visit": this.#visitStarted,
      "turbo:load": this.#visitFinished,
      "turbo:before-render": this.#beforeRender,
      "turbo:before-fetch-response": this.#beforeResponse,
      "turbo:fetch-request-error": this.#fetchError,
      "turbo:submit-start": this.#submitStarted,
      "turbo:submit-end": this.#submitEnded
    }
    for (const [name, action] of Object.entries(actions)) document.addEventListener(name, action, { signal })
    window.addEventListener("popstate", this.#beforeRestore, { capture: true, signal })
  }

  disconnect() {
    this.listeners.abort()
    this.candidate = this.active = this.submission = null
  }

  get atEditorEntry() {
    return !this.returning && this.#isEditorEntry(window.history.state?.turbo)
  }

  #beforeVisit = (event) => {
    if (event.defaultPrevented) return

    const { url } = event.detail
    const submission = this.#activeSubmission
    const response = submission?.formSubmission.result?.fetchResponse
    // A redirect uses the form's consent, but the render still checks for edits
    // made during the request.
    const consent = response?.succeeded && response.location.href === url ? submission : this.#approve()
    if (consent) this.#propose({ url, serial: consent.serial })
    else event.preventDefault()
  }

  #propose(candidate) {
    this.candidate = candidate
    queueMicrotask(() => {
      if (this.candidate === candidate) this.candidate = null
    })
  }

  #visitStarted = (event) => {
    const visit = Turbo.navigator.currentVisit
    if (!visit?.willRender) return

    const { url, action } = event.detail
    const candidate = this.candidate?.url === url ? this.candidate : null
    if (!candidate && action !== "restore") return

    this.active = { visit, serial: candidate?.serial ?? null, updateHistory: visit.updateHistory }
    this.candidate = this.submission = null
    // Turbo normally changes history before before-render (and before any
    // render interception completes). Commit it with the actual body render.
    visit.updateHistory = false
  }

  #visitFinished = () => {
    if (this.active && this.active.visit.state !== "started") {
      this.active = null
      this.entry = window.history.state?.turbo
    }
  }

  #beforeRender = (event) => {
    const departure = this.#activeVisit
    if (!departure) return

    if (departure.visit.response?.statusCode >= 400) {
      // ErrorRenderer replaces the head before calling detail.render. Guard this
      // renderer instance instead, after any interception but before either swap.
      const renderer = departure.visit.view.renderer
      const renderError = renderer.render.bind(renderer)
      renderer.render = () => {
        if (this.#commitRender(departure)) return renderError()
      }
      return
    }

    const { render, renderMethod } = event.detail
    const preview = document.documentElement.hasAttribute("data-turbo-preview")
    event.detail.render = (currentBody, newBody) => {
      if (departure !== this.#activeVisit || !this.form.isConnected) return

      // A cached preview must not unmount the editor before the GET succeeds.
      if (preview) {
        Turbo.cache.exemptPageFromCache()
        return
      }

      if (!this.#commitRender(departure)) return
      if (this.draftSerial() !== null && renderMethod === "morph") this.form.remove()
      return render(currentBody, newBody)
    }
  }

  #commitRender(departure) {
    if (departure !== this.#activeVisit || !this.form.isConnected) return false

    const serial = this.draftSerial()
    if (serial !== null && serial !== departure.serial && !this.confirmDiscard()) {
      this.#cancelVisit(departure)
      Turbo.cache.exemptPageFromCache()
      return false
    }

    departure.visit.updateHistory = departure.updateHistory
    departure.visit.changeHistory()
    return true
  }

  #submitStarted = (event) => {
    const { formSubmission } = event.detail
    if (event.target === this.form || formSubmission.delegate !== Turbo.navigator) return

    // Turbo's action-specific confirmation has already run; the request hasn't.
    const consent = this.#approve()
    if (consent) this.submission = { formSubmission, serial: consent.serial }
    else formSubmission.stop()
  }

  #submitEnded = (event) => {
    if (event.detail.formSubmission === this.submission?.formSubmission && !event.detail.success) this.submission = null
  }

  #beforeResponse = (event) => {
    if (!this.form.isConnected || this.draftSerial() === null) return

    const { fetchResponse } = event.detail
    const { statusCode } = fetchResponse
    const staleDestination = statusCode === 404 && fetchResponse.header("X-Notes-Draft-Recovery") === "unavailable"
    // Unmarked 404s, 401s, and 403s retain normal access handling.
    if (!staleDestination && statusCode !== 409 && statusCode !== 422 && !fetchResponse.serverError) return

    const departure = this.#activeVisit
    const submission = this.#activeSubmission
    if (event.target === document.documentElement && this.#isVisitResponse(departure, fetchResponse)) {
      event.preventDefault()
      this.#cancelVisit(departure)
      this.onFailure("navigation_failed")
    } else if (event.target === submission?.formSubmission.formElement) {
      event.preventDefault()
      this.onFailure(statusCode === 409 ? "unavailable" : "action_failed")
    }
  }

  #isVisitResponse(departure, response) {
    const request = departure?.visit.request
    if (!request || request.abortSignal.aborted) return false

    const url = new URL(request.url)
    url.hash = ""
    return response.redirected || response.location.href === url.href
  }

  #fetchError = (event) => {
    const departure = this.#activeVisit
    if (event.target !== document.documentElement || !departure ||
        event.detail.request !== departure.visit.request || !this.form.isConnected || this.draftSerial() === null) return

    event.preventDefault()
    this.#cancelVisit(departure)
    this.onFailure("navigation_failed")
  }

  #beforeRestore = (event) => {
    const next = event.state?.turbo
    if (this.returning && this.#isEditorEntry(next)) {
      this.#cancelRestore(event)
      this.returning = false
      this.onReturn()
      return
    }

    const offset = this.#restoreOffset(next)
    if (!offset) return

    const consent = this.#approve()
    if (!consent) {
      this.#cancelRestore(event)
      this.#returnToEditor(offset)
      return
    }

    const url = window.location.href
    const departure = this.#activeVisit
    if (departure?.visit.action === "restore" && departure.visit.location.href === url) departure.serial = consent.serial
    else this.#propose({ url, serial: consent.serial })
  }

  #approve() {
    const serial = this.draftSerial()
    if (serial !== null && !this.confirmDiscard()) return null

    return { serial }
  }

  get #activeVisit() {
    const visit = Turbo.navigator.currentVisit
    return this.active?.visit === visit && visit?.state === "started" ? this.active : null
  }

  get #activeSubmission() {
    return this.submission?.formSubmission === Turbo.navigator.formSubmission ? this.submission : null
  }

  #isEditorEntry(entry) {
    return this.entry?.restorationIdentifier === entry?.restorationIdentifier
  }

  #restoreOffset(next) {
    if (this.entry && Number.isInteger(next?.restorationIndex)) return this.entry.restorationIndex - next.restorationIndex
  }

  #cancelVisit(departure) {
    // A replacement visit may have aborted Back while the browser still sits
    // at its destination. Roll back from the actual entry to the mounted editor.
    const offset = this.#restoreOffset(window.history.state?.turbo)
    this.#stopVisit(departure.visit)
    if (offset) this.#returnToEditor(offset)
  }

  #returnToEditor(offset) {
    this.returning = true
    window.history.go(offset)
  }

  #cancelRestore(event) {
    event.stopImmediatePropagation()
    const visit = Turbo.navigator.currentVisit
    if (visit?.action === "restore" && visit.state === "started") this.#stopVisit(visit)
  }

  #stopVisit(visit) {
    this.active = null
    Turbo.navigator.stop()
    Turbo.session.adapter.visitFailed(visit)
    Turbo.session.view.unmarkVisitDirection()
    document.documentElement.removeAttribute("aria-busy")
  }
}
