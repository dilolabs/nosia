import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "label"]
  static values = { content: String }

  copy() {
    // Récupérer le contenu depuis l'attribut data ou depuis le parent
    const text = this.contentValue || this.element.innerText || this.element.textContent || ""

    navigator.clipboard?.writeText(text).then(() => {
      // Feedback visuel
      if (this.hasLabelTarget) {
        const originalText = this.labelTarget.textContent
        this.labelTarget.textContent = "Copié !"

        setTimeout(() => {
          this.labelTarget.textContent = originalText
        }, 2000)
      }
    }).catch(err => {
      console.error("Erreur lors de la copie:", err)
    })
  }
}
