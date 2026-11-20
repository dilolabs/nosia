import { Controller } from "@hotwired/stimulus"

// Shows the fields applicable to the selected transport and credential mode.
export default class extends Controller {
  static targets = [ "httpFields", "stdioFields", "staticFields" ]

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    const type = this.element.querySelector('[name="mcp_server[transport_type]"]')?.value
    const mode = this.element.querySelector('[name="mcp_server[auth_mode]"]')
    const oauth = mode?.querySelector('option[value="oauth"]')
    if (oauth) oauth.disabled = type !== "streamable" && !oauth.selected
    const http = [ "streamable", "sse" ].includes(type)
    const groups = [
      [ this.httpFieldsTargets, http ],
      [ this.stdioFieldsTargets, type === "stdio" ],
      [ this.staticFieldsTargets, http && mode?.value !== "oauth" ]
    ]
    for (const [ targets, visible ] of groups) {
      targets.forEach(group => {
        if (visible && group.hidden && group instanceof HTMLDetailsElement) group.open = true
        group.hidden = !visible
        group.querySelectorAll("input, textarea, select").forEach(input => {
          input.disabled = !visible
          input.required = visible && input.dataset.mcpRequired === "true"
        })
      })
    }
  }
}
