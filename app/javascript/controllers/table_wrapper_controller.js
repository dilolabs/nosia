import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.wrapTables()

    // Observer to wrap dynamically added tables (streaming)
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
      // Check if the table is not already wrapped
      if (!table.parentElement.classList.contains('table-wrapper')) {
        const wrapper = document.createElement('div')
        wrapper.className = 'table-wrapper'

        // Insert the wrapper before the table
        table.parentNode.insertBefore(wrapper, table)

        // Move the table into the wrapper
        wrapper.appendChild(table)

        // Mark as wrapped
        table.classList.add('wrapped')
      }
    })
  }
}
