import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea","counter"]
  connect(){ this.autogrow() }

  autogrow(){
    const ta = this.textareaTarget
    ta.style.height = "auto"
    ta.style.overflow = "hidden"
    ta.style.height = ta.scrollHeight + "px"
    if (this.hasCounterTarget) this.counterTarget.textContent = `${ta.value.length} / 3000`
  }

  handleKeys(e){
    if (e.key !== "Enter") return
    if (e.shiftKey) {            // Shift+Enter = nouvelle ligne
      return                      // laisser le comportement natif
    }
    e.preventDefault()            // Enter seul = envoyer
    this.element.requestSubmit()
  }

  submit(){ }
}
