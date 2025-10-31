import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.wrapTables()

    // Observer pour wrapper les tableaux ajoutés dynamiquement (streaming)
    this.observer = new MutationObserver(() => {
      this.wrapTables()
    })

    this.observer.observe(this.element, {
      childList: true,
      subtree: true
    })
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  wrapTables() {
    const tables = this.element.querySelectorAll('table:not(.wrapped)')

    tables.forEach(table => {
      // Vérifier si le tableau n'est pas déjà wrappé
      if (!table.parentElement.classList.contains('table-wrapper')) {
        const wrapper = document.createElement('div')
        wrapper.className = 'table-wrapper'

        // Insérer le wrapper avant le tableau
        table.parentNode.insertBefore(wrapper, table)

        // Déplacer le tableau dans le wrapper
        wrapper.appendChild(table)

        // Marquer comme wrappé
        table.classList.add('wrapped')
      }
    })
  }
}
