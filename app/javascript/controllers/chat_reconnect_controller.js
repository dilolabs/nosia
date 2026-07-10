import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Recovers the chat view when it misses live Turbo Stream broadcasts (a dropped or
// cold ActionCable subscription), which would otherwise leave the UI stuck on
// "Preparing" (or the streaming placeholder) until a manual refresh.
//
// While the chat is generating, it watches incoming stream activity. If nothing
// arrives for `timeout` ms — i.e. we appear stuck — it performs a same-URL Turbo
// visit, which is a morph page refresh (see the turbo-refresh-* metas): the view is
// re-rendered from the DB without tearing down the DOM, the cable subscription, or
// scroll position. When the stream is flowing normally, activity keeps resetting the
// timer so it never fires and never clobbers the live stream.
//
// finish_generation! also broadcasts a morph refresh, so the final state self-heals
// even if the last broadcasts were missed; this poll covers the long wait before that.
export default class extends Controller {
  static values = {
    generating: Boolean,
    timeout: { type: Number, default: 10000 },
    interval: { type: Number, default: 2500 }
  }

  connect() {
    this.markActivity = this.markActivity.bind(this)
    this.onVisible = this.onVisible.bind(this)
    // Any incoming stream (message append, phase update, streamed content) counts
    // as activity; a page refresh triggered by the morph also renders streams.
    document.addEventListener("turbo:before-stream-render", this.markActivity)
    document.addEventListener("visibilitychange", this.onVisible)
  }

  disconnect() {
    this.stop()
    document.removeEventListener("turbo:before-stream-render", this.markActivity)
    document.removeEventListener("visibilitychange", this.onVisible)
  }

  generatingValueChanged() {
    this.generatingValue ? this.start() : this.stop()
  }

  start() {
    this.markActivity()
    if (this.timer) return
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  markActivity() {
    this.lastActivityAt = Date.now()
  }

  onVisible() {
    // A tab returning to the foreground is the most common moment to discover it
    // missed broadcasts while backgrounded — check immediately instead of waiting.
    if (!document.hidden) this.tick()
  }

  tick() {
    if (!this.generatingValue || document.hidden) return
    if (Date.now() - this.lastActivityAt < this.timeoutValue) return

    // Reset before visiting so the re-rendered controller doesn't reconcile again
    // immediately if it's still (legitimately) generating.
    this.markActivity()
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
