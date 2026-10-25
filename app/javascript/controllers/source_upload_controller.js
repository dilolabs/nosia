import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input"];
  static values = { labels: Object };

  browse() {
    if (this.element.isConnected && !this.element.closest("[inert]")) this.inputTarget.click();
  }

  labelUploads() {
    this.element.querySelectorAll("[data-upload-status]").forEach(entry => {
      let label = entry.querySelector("[data-source-upload-label]");
      if (!label) {
        label = document.createElement("span");
        label.dataset.sourceUploadLabel = "";
        entry.append(label);
      }
      label.textContent = this.labelsValue[entry.dataset.uploadStatus] || "";
    });
  }
}
