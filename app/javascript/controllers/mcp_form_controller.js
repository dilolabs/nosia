import { Controller } from "@hotwired/stimulus"

// Enables only the fields belonging to the selected transport.
export default class extends Controller {
  static targets = [ "httpFields", "stdioFields" ]

  connect() {
    this.toggleTransportFields()
    this.transport = this.element.querySelector('[name="mcp_server[transport_type]"]')
    this.change = () => this.toggleTransportFields()
    this.transport?.addEventListener("change", this.change)
  }

  disconnect() {
    this.transport?.removeEventListener("change", this.change)
  }

  toggleTransportFields() {
    const type = this.element.querySelector('[name="mcp_server[transport_type]"]')?.value
    for (const [ targets, visible ] of [ [ this.httpFieldsTargets, [ "streamable", "sse" ].includes(type) ], [ this.stdioFieldsTargets, type === "stdio" ] ]) {
      targets.forEach(group => {
        group.hidden = !visible
        group.querySelectorAll("input, textarea, select").forEach(input => {
          input.disabled = !visible
          input.required = visible && input.dataset.mcpRequired === "true"
        })
      })
    }
  }
}
