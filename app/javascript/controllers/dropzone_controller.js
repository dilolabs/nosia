import { Controller } from "@hotwired/stimulus";
import Dropzone from "dropzone";

export default class extends Controller {
  connect() {
    const dropzoneConfig = {
      url: this.url,
      method: "post",
      withCredentials: false,
      parallelUploads: "5",
      uploadMultiple: false,
      maxFilesize: 256,
      paramName: "document[file]",
      maxFiles: 50,
      clickable: true,
      acceptedFiles: "application/pdf,text/*,.md",
      addRemoveLinks: false,
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
      },
    };

    this.dropzone = new Dropzone(this.element, dropzoneConfig);
  }

  get url() {
    return `/sources/documents`;
  }
}
