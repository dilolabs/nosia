import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  requestHTML(event) {
    const form = event.target
    const { fetchOptions } = event.detail

    if (form instanceof HTMLFormElement && form.hasAttribute("hidden") && fetchOptions.method.toUpperCase() === "DELETE") {
      const matchesSource = Array.from(this.element.querySelectorAll('a[data-turbo-method="delete"]'))
        .some(link => link.href === form.action)

      if (matchesSource) fetchOptions.headers.Accept = "text/html, application/xhtml+xml"
    }
  }
}
