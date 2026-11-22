import { Turbo } from "@hotwired/turbo-rails"
import NotesActionDialogController from "controllers/notes_action_dialog_controller"

export default class extends NotesActionDialogController {
  rememberDestination(event) {
    const select = event.currentTarget
    if (event.target !== select) return

    this.destinationBeforeMorph = this.pickerOpen && event.detail.newElement ? { select, value: select.value } : null
  }

  restoreDestination(event) {
    const select = event.currentTarget
    if (event.target !== select) return

    const previous = this.destinationBeforeMorph
    this.destinationBeforeMorph = null
    if (previous?.select !== select || !select.isConnected || !this.pickerOpen) return

    // Turbo skips the children of the focused select. Refresh them without moving focus.
    if (select === document.activeElement) Turbo.morphChildren(select, event.detail.newElement)
    const available = Array.from(select.options).some(option => option.value === previous.value && !option.matches(":disabled"))
    select.value = available ? previous.value : ""
  }

  get pickerOpen() {
    return this.hasPanelTarget && this.panelTarget.matches(":popover-open, :modal")
  }
}
