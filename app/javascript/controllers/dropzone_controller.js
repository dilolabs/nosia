import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["container", "input", "list"];
  static values = {
    url: String,
    maxFileSize: { type: Number, default: 50 }, // in MB
    acceptedFiles: String, // comma-separated MIME types
    multiple: Boolean,
    variant: String, // "dashboard" or "minimal"
    parallelLimit: { type: Number, default: 5 }
  };

  connect() {
    this.activeUploads = [];
    this.uploadQueue = [];
    this.filesByName = new Map();
    this.xhrsByFileName = new Map();
    this._bindEvents();
  }

  disconnect() {
    this._abortAllUploads();
  }

  _bindEvents() {
    // Drag events on container
    this.containerTarget.addEventListener("dragenter", (e) => this._highlight(e));
    this.containerTarget.addEventListener("dragover", (e) => this._highlight(e));
    this.containerTarget.addEventListener("dragleave", (e) => this._unhighlight(e));
    this.containerTarget.addEventListener("drop", (e) => this._handleDrop(e));

    // Click to browse
    this.containerTarget.addEventListener("click", () => this.inputTarget.click());
    this.inputTarget.addEventListener("change", (e) => this._handleFileSelect(e));

    // Prevent default drag behavior on the whole page while dragging over dropzone
    document.addEventListener("dragover", (e) => {
      if (this.element.contains(e.target)) e.preventDefault();
    });
  }

  _highlight() {
    this.containerTarget.dataset.active = "true";
  }

  _unhighlight() {
    this.containerTarget.dataset.active = "false";
  }

  _handleDrop(e) {
    e.preventDefault();
    this._unhighlight();
    const files = Array.from(e.dataTransfer.files);
    this._processFiles(files);
  }

  _handleFileSelect(e) {
    const files = Array.from(e.target.files);
    this._processFiles(files);
    // Reset input so same file can be selected again if removed
    e.target.value = "";
  }

  _processFiles(files) {
    // Filter out duplicates (by name) and invalid files
    const uniqueFiles = files.filter(
      (file) => !this.filesByName.has(file.name) && !this.uploadQueue.find((f) => f.name === file.name)
    );

    uniqueFiles.forEach((file) => {
      if (this._validateFile(file)) {
        this.filesByName.set(file.name, file);
        this.uploadQueue.push(file);
        this._renderFileEntry(file, "pending");
        this._dequeueNext();
      } else {
        this._showValidationError(file);
      }
    });
  }

  _validateFile(file) {
    // Check file size - ensure we have a valid number with robust fallback
    let maxSizeMB = parseInt(this.maxFileSizeValue, 10);
    
    // If parsing fails or value is invalid, use default of 50 MB
    if (isNaN(maxSizeMB) || maxSizeMB <= 0) {
      maxSizeMB = 50;
    }
    
    const maxSizeBytes = maxSizeMB * 1024 * 1024;
    
    if (file.size > maxSizeBytes) {
      return false;
    }

    // Check file type if acceptedFiles is set
    if (this.acceptedFilesValue) {
      const allowedTypes = this.acceptedFilesValue.split(",").map((t) => t.trim());
      const fileType = file.type || "application/octet-stream";
      const matches = allowedTypes.some((type) => {
        if (type.endsWith("/*")) {
          return fileType.startsWith(type.slice(0, -2));
        }
        return type === fileType;
      });
      if (!matches) return false;
    }

    return true;
  }

  _renderFileEntry(file, status) {
    const li = document.createElement("li");
    li.dataset.fileName = file.name;
    li.className = this._entryClassName();

    // Status mark (icon + color)
    const statusMark = document.createElement("span");
    statusMark.className = "status-mark flex-shrink-0 w-4 h-4 rounded-full border-2";
    if (status === "pending") {
      statusMark.classList.add("border-neutral-300", "dark:border-neutral-600");
    } else if (status === "uploading") {
      statusMark.classList.add("border-blue-500", "animate-pulse");
    } else if (status === "success") {
      statusMark.classList.add("bg-green-500", "border-green-500");
      statusMark.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke-width="3" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>`;
    } else if (status === "error") {
      statusMark.classList.add("bg-red-500", "border-red-500");
      statusMark.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke-width="3" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`;
    }

    // File name
    const fileName = document.createElement("span");
    fileName.className = "file-name truncate flex-1 text-neutral-700 dark:text-neutral-200";
    fileName.textContent = file.name;

    li.appendChild(statusMark);
    li.appendChild(fileName);

    // Remove button (only for dashboard variant)
    if (this.variantValue === "dashboard") {
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.dataset.action = "dropzone#removeFile";
      removeBtn.className = "remove-btn flex-shrink-0 w-5 h-5 rounded-full hover:bg-neutral-200 dark:hover:bg-neutral-600 flex items-center justify-center text-neutral-400 hover:text-neutral-600 dark:hover:text-neutral-300";
      removeBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`;
      li.appendChild(removeBtn);

      // Retry button (only for error state)
      if (status === "error") {
        const retryBtn = document.createElement("button");
        retryBtn.type = "button";
        retryBtn.dataset.action = "dropzone#retryFile";
        retryBtn.className = "retry-btn flex-shrink-0 text-xs text-blue-600 hover:text-blue-800 dark:hover:text-blue-400 ml-2";
        retryBtn.textContent = "Retry";
        li.appendChild(retryBtn);
      }
    }

    this.listTarget.appendChild(li);
    if (this.listTarget.children.length === 1) {
      this.listTarget.classList.remove("hidden");
    }
  }

  _entryClassName() {
    if (this.variantValue === "dashboard") {
      return "flex items-center gap-2 px-3 py-2 rounded-lg bg-neutral-50 dark:bg-neutral-700/50 text-sm";
    }
    return "flex items-center gap-2 px-2 py-1.5 text-sm text-neutral-700 dark:text-neutral-200";
  }

  _showValidationError(file) {
    const li = document.createElement("li");
    li.dataset.fileName = file.name;
    li.className = "flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 dark:bg-red-900/30 text-sm text-red-700 dark:text-red-300";

    const icon = document.createElement("span");
    icon.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" /></svg>`;

    const message = document.createElement("span");
    message.textContent = this._validationErrorMessage(file);

    li.appendChild(icon);
    li.appendChild(message);

    this.listTarget.appendChild(li);
    if (this.listTarget.children.length === 1) {
      this.listTarget.classList.remove("hidden");
    }
  }

  _validationErrorMessage(file) {
    const maxSizeBytes = this.maxFileSizeValue * 1024 * 1024;
    if (file.size > maxSizeBytes) {
      return `File too large. Maximum size is ${this.maxFileSizeValue} MB.`;
    }
    if (this.acceptedFilesValue) {
      return "Invalid file type.";
    }
    return "Upload failed.";
  }

  _dequeueNext() {
    if (this.activeUploads.length >= this.parallelLimitValue || this.uploadQueue.length === 0) {
      return;
    }

    const file = this.uploadQueue.shift();
    this._uploadFile(file);
  }

  async _uploadFile(file) {
    // Update status to uploading
    const entry = this.listTarget.querySelector(`[data-file-name="${file.name}"]`);
    if (entry) {
      const statusMark = entry.querySelector(".status-mark");
      if (statusMark) {
        statusMark.className = "status-mark flex-shrink-0 w-4 h-4 rounded-full border-2 border-blue-500 animate-pulse";
      }
    }

    this.activeUploads.push(file);

    const xhr = new XMLHttpRequest();
    this.xhrsByFileName.set(file.name, xhr);

    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && entry) {
        const percent = Math.round((event.loaded / event.total) * 100);
        // Could add progress bar here if needed
      }
    };

    xhr.onload = () => {
      this.activeUploads = this.activeUploads.filter((f) => f.name !== file.name);
      this.xhrsByFileName.delete(file.name);
      
      if (xhr.status >= 200 && xhr.status < 300) {
        // Success
        if (entry) {
          const statusMark = entry.querySelector(".status-mark");
          if (statusMark) {
            statusMark.className = "status-mark flex-shrink-0 w-4 h-4 rounded-full bg-green-500 border-2 border-green-500";
            statusMark.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke-width="3" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>`;
          }
        }
      } else {
        // Error
        if (entry) {
          const statusMark = entry.querySelector(".status-mark");
          if (statusMark) {
            statusMark.className = "status-mark flex-shrink-0 w-4 h-4 rounded-full bg-red-500 border-2 border-red-500";
            statusMark.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke-width="3" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`;
          }
        }
      }
      this._dequeueNext();
    };

    xhr.onerror = () => {
      this.activeUploads = this.activeUploads.filter((f) => f.name !== file.name);
      this.xhrsByFileName.delete(file.name);
      
      if (entry) {
        const statusMark = entry.querySelector(".status-mark");
        if (statusMark) {
          statusMark.className = "status-mark flex-shrink-0 w-4 h-4 rounded-full bg-red-500 border-2 border-red-500";
          statusMark.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke-width="3" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`;
        }
      }
      this._dequeueNext();
    };

    const formData = new FormData();
    // Add document parameters - title is required by the controller
    formData.append("document[title]", file.name);
    formData.append("document[file]", file);

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || "";
    xhr.open("POST", this.urlValue, true);
    xhr.setRequestHeader("X-CSRF-Token", csrfToken);
    xhr.send(formData);
  }

  removeFile(e) {
    e.stopPropagation();
    const entry = e.currentTarget.closest("[data-file-name]");
    if (!entry) return;
    const fileName = entry.dataset.fileName;

    // Abort XHR if active (tracked in Task 2)
    const xhr = this.xhrsByFileName?.get(fileName);
    if (xhr) {
      xhr.abort();
      this.xhrsByFileName.delete(fileName);
    }

    // Remove from queues
    this.activeUploads = this.activeUploads.filter((f) => f.name !== fileName);
    this.uploadQueue = this.uploadQueue.filter((f) => f.name !== fileName);
    this.filesByName?.delete(fileName);

    entry.remove();
    if (this.listTarget.children.length === 0) {
      this.listTarget.classList.add("hidden");
    }
  }

  retryFile(e) {
    e.stopPropagation();
    const entry = e.currentTarget.closest("[data-file-name]");
    if (!entry) return;
    const fileName = entry.dataset.fileName;
    const file = this.filesByName?.get(fileName);
    if (file) {
      // Remove error styling from old entry
      entry.remove();
      // Re-render as pending and re-queue
      this._renderFileEntry(file, "pending");
      this.uploadQueue.push(file);
      this._dequeueNext();
    }
  }

  _abortAllUploads() {
    // Abort all active XHRs (tracked in Task 2)
    if (this.xhrsByFileName) {
      this.xhrsByFileName.forEach((xhr) => xhr.abort());
      this.xhrsByFileName.clear();
    }
    this.activeUploads = [];
    this.uploadQueue = [];
  }
}
