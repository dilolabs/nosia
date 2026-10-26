import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  requestHTML(event) {
    if (event.target !== this.element) return
    const headers = event.detail.fetchOptions.headers
    if (headers instanceof Headers) headers.set("Accept", "text/html, application/xhtml+xml")
    else headers.Accept = "text/html, application/xhtml+xml"
  }
}
