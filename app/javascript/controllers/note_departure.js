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
    document.addEventListener("submit", this.#beforeSubmit, { capture: true, signal })
    window.addEventListener("popstate", this.#beforeRestore, { capture: true, signal })
  }

  disconnect() {
    this.listeners.abort()
    this.candidate = this.active = null
    this.returning?.()
    this.returning = null
  }

  get atEditorEntry() {
    return !this.returning && this.#isEditorEntry(window.history.state?.turbo)
  }

  #beforeVisit = (event) => {
    if (event.defaultPrevented) return

    const { url } = event.detail
    const departure = this.#activeDeparture
    const response = departure?.formSubmission?.result?.fetchResponse
    // A redirect uses the form's consent, but the render still checks for edits
    // made during the request.
    const fromForm = response?.succeeded && response.location.href === url
    const consent = fromForm ? departure : this.#approve()
    if (consent) this.#propose({ url, serial: consent.serial, fromForm })
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

    this.active = { visit, serial: candidate?.serial ?? null, fromForm: candidate?.fromForm, updateHistory: visit.updateHistory }
    this.candidate = null
    // Turbo normally changes history before before-render (and before any
    // render interception completes). Commit it with the actual body render.
    visit.updateHistory = false
  }

  #visitFinished = () => {
    if (this.active?.visit && this.active.visit.state !== "started") {
      this.active = null
      this.entry = window.history.state?.turbo
    }
  }

  #beforeRender = (event) => {
    const error = this.renderingForm
    const formError = error && error.body === event.detail.newBody ? error.departure : null
    const departure = formError || this.#activeDeparture
    if (!formError && !departure?.visit) return

    if (formError || departure.visit.response?.statusCode >= 400) {
      // ErrorRenderer replaces the head before calling detail.render. Guard this
      // renderer instance instead, after any interception but before either swap.
      const renderer = Turbo.session.view.renderer
      const renderError = renderer.render.bind(renderer)
      renderer.render = () => {
        if (this.#commitRender(departure)) return renderError()
      }
      return
    }

    const { render, renderMethod } = event.detail
    const preview = document.documentElement.hasAttribute("data-turbo-preview")
    event.detail.render = (currentBody, newBody) => {
      if (!this.#isCurrent(departure)) return

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
    if (!this.#allowsRender(departure)) return false

    if (departure.visit) {
      departure.visit.updateHistory = departure.updateHistory
      departure.visit.changeHistory()
    } else {
      Turbo.cache.clear()
    }
    return true
  }

  #allowsRender(departure) {
    if (!this.#isCurrent(departure)) return false

    const serial = this.draftSerial()
    if (serial !== null && serial !== departure.serial) {
      if (!this.confirmDiscard()) {
        const message = departure.formSubmission ? "action_failed" : departure.fromForm ? "unsaved" : null
        this.#keepEditor(departure, message)
        Turbo.cache.exemptPageFromCache()
        return false
      }
      departure.serial = serial
    }
    return true
  }

  #beforeSubmit = (event) => {
    const pending = this.active
    if (!pending || event.target === this.form || this.atEditorEntry) return

    // Turbo stops the old navigation before asking its native form question.
    // A declined action never emits submit-start or submit-end.
    requestAnimationFrame(() => {
      const submission = Turbo.navigator.formSubmission
      if (this.active === pending && submission?.formElement === event.target && submission.state === "initialized" &&
          this.#activeDeparture !== pending) {
        this.#keepEditor(pending)
      }
    })
  }

  #submitStarted = (event) => {
    const { formSubmission } = event.detail
    if (formSubmission.formElement === this.form || formSubmission.delegate !== Turbo.navigator) return

    // Navigator has already aborted an earlier visit. Clear its UI, but keep
    // the mounted editor's entry as the rollback point for this submission.
    if (this.active?.visit) this.#finishVisit(this.active.visit)

    const departure = this.active = { formSubmission }
    const consent = this.#approve()
    if (consent) departure.serial = consent.serial
    else this.#keepEditor(departure)
  }

  #submitEnded = (event) => {
    const departure = this.#activeDeparture
    if (event.detail.formSubmission === departure?.formSubmission && !event.detail.fetchResponse) {
      this.#keepEditor(departure)
    }
  }

  #beforeResponse = (event) => {
    const departure = this.#activeDeparture
    if (event.defaultPrevented || !departure || !this.form.isConnected) return

    const { fetchResponse } = event.detail
    const submission = departure.formSubmission
    const visitResponse = event.target === document.documentElement && this.#isVisitResponse(departure, fetchResponse)
    const formResponse = event.target === submission?.formElement && !submission.fetchRequest.abortSignal.aborted
    if (!visitResponse && !formResponse) return

    const { statusCode, serverError } = fetchResponse
    const staleDestination = statusCode === 404 && fetchResponse.header("X-Notes-Draft-Recovery") === "unavailable"
    if (this.draftSerial() !== null && (staleDestination || statusCode === 409 || statusCode === 422 || serverError)) {
      event.preventDefault()
      const message = visitResponse ? "navigation_failed" : statusCode === 409 ? "unavailable" : "action_failed"
      this.#keepEditor(departure, message)
    } else if (formResponse && !fetchResponse.succeeded) {
      event.preventDefault()
      this.#renderFormError(departure, fetchResponse)
    }
  }

  async #renderFormError(departure, response) {
    const html = await response.responseHTML.catch(() => null)
    if (!this.#isCurrent(departure)) return
    if (!html) {
      this.#keepEditor(departure)
      return
    }

    await this.#restoreEditorEntry()
    const { view } = Turbo.session
    if (view.renderPromise) await view.renderPromise
    if (!this.#isCurrent(departure)) return

    // Failed forms don't start a visit. Use the same guarded error renderer
    // as GET failures; a standalone 404 would otherwise force a GET reload.
    const snapshot = Turbo.PageSnapshot.fromHTMLString(html)
    this.renderingForm = { departure, body: snapshot.element }
    try {
      await view.renderError(snapshot)
      if (departure === this.#activeDeparture) {
        if (snapshot.refreshScroll !== "preserve") view.scrollToTop()
        this.active = null
      }
    } finally {
      this.renderingForm = null
    }
  }

  #isVisitResponse(departure, response) {
    const request = departure.visit?.request
    if (!request || request.abortSignal.aborted) return false

    const url = new URL(request.url)
    url.hash = ""
    return response.redirected || response.location.href === url.href
  }

  #fetchError = (event) => {
    const departure = this.#activeDeparture
    if (!departure || !this.form.isConnected || this.draftSerial() === null) return

    const { request } = event.detail
    const visit = request === departure.visit?.request
    if (!visit && request !== departure.formSubmission?.fetchRequest) return

    event.preventDefault()
    this.#keepEditor(departure, visit ? "navigation_failed" : "action_failed")
  }

  #beforeRestore = (event) => {
    const next = event.state?.turbo
    if (this.returning && this.#isEditorEntry(next)) {
      this.#cancelRestore(event)
      // Turbo's own popstate listener didn't run. Sync its cursor without
      // rewriting the browser entry so subsequent visits start here too.
      const location = new URL(window.location.href)
      const { history, view } = Turbo.session
      history.location = view.lastRenderedLocation = location
      history.currentIndex = next.restorationIndex
      history.restorationIdentifier = next.restorationIdentifier
      const returned = this.returning
      this.returning = null
      this.onReturn()
      returned()
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
    const departure = this.#activeDeparture
    if (departure?.visit?.action === "restore" && departure.visit.location.href === url) departure.serial = consent.serial
    else this.#propose({ url, serial: consent.serial })
  }

  #approve() {
    const serial = this.draftSerial()
    if (serial !== null && !this.confirmDiscard()) return null

    return { serial }
  }

  #isCurrent(departure) {
    return departure === this.#activeDeparture && this.form.isConnected
  }

  get #activeDeparture() {
    const { currentVisit, formSubmission } = Turbo.navigator
    if (this.active?.visit === currentVisit && currentVisit?.state === "started") return this.active
    if (formSubmission && this.active?.formSubmission === formSubmission) return this.active
    return null
  }

  #isEditorEntry(entry) {
    return this.entry?.restorationIdentifier === entry?.restorationIdentifier
  }

  #restoreOffset(next) {
    if (this.entry && Number.isInteger(next?.restorationIndex)) return this.entry.restorationIndex - next.restorationIndex
  }

  #keepEditor(departure, message) {
    this.active = null
    Turbo.navigator.stop()
    if (departure.visit) this.#finishVisit(departure.visit)
    this.#restoreEditorEntry()
    if (message) this.onFailure(message)
  }

  #restoreEditorEntry() {
    // Back may have been superseded without moving the browser's history.
    const offset = this.#restoreOffset(window.history.state?.turbo)
    if (offset) return this.#returnToEditor(offset)
  }

  #returnToEditor(offset) {
    return this.returnPromise ??= new Promise(resolve => {
      this.returning = () => {
        this.returnPromise = null
        resolve()
      }
      window.history.go(offset)
    })
  }

  #cancelRestore(event) {
    event.stopImmediatePropagation()
    const visit = Turbo.navigator.currentVisit
    if (visit?.action === "restore" && visit.state === "started") {
      this.active = null
      Turbo.navigator.stop()
      this.#finishVisit(visit)
    }
  }

  #finishVisit(visit) {
    Turbo.session.adapter.visitFailed(visit)
    Turbo.session.view.unmarkVisitDirection()
    document.documentElement.removeAttribute("aria-busy")
  }
}
