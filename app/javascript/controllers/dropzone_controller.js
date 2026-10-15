import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["container", "input", "list"];
  static values = {
    accountId: String,
    url: String,
    maxFileSize: { type: Number, default: 50 }, // in MB
    acceptedFiles: String, // comma-separated MIME types
    multiple: Boolean,
    variant: String, // "dashboard" or "minimal"
    parallelLimit: { type: Number, default: 5 },
    clickToBrowse: { type: Boolean, default: true }
  };

  connect() {
    this.activeUploads = [];
    this.uploadQueue = [];
    this.filesByName = new Map();
    this.uploadIdsByFileName = new Map();
    this.xhrsByFileName = new Map();
    if (!this.hasVariantValue) this.variantValue = this.element.dataset.variant || "";
    this._bindEvents();
    queueMicrotask(() => this._publishChatSourceState());
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

    // Click to browse — opt-out so a full-list drop zone doesn't hijack row clicks
    if (this.clickToBrowseValue) {
      this.containerTarget.addEventListener("click", () => {
        if (this.element.isConnected && !this.element.closest("[inert]")) this.inputTarget.click();
      });
    }
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
    if (!this.element.isConnected || this.element.closest("[inert]")) return;

    // Filter out duplicates (by name) and invalid files
    const uniqueFiles = files.filter(
      (file) => !this.filesByName.has(file.name) && !this.uploadQueue.find((f) => f.name === file.name)
    );

    uniqueFiles.forEach((file) => {
      if (this._validateFile(file)) {
        this.filesByName.set(file.name, file);
        this.uploadIdsByFileName.set(file.name, crypto.randomUUID());
        this.uploadQueue.push(file);
        this._renderFileEntry(file, "pending");
        this._dequeueNext();
      } else {
        this._showValidationError(file);
      }
    });
    this._publishChatSourceState();
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
    li.dataset.uploadStatus = status;
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

    if (status === "error") {
      const alert = document.createElement("span");
      alert.setAttribute("role", "alert");
      alert.textContent = "Upload failed. Retry or remove.";
      li.appendChild(alert);
    }

    // Remove button (only for dashboard variant)
    if (this.variantValue === "dashboard") {
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.setAttribute("aria-label", "Remove upload");
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
    li.dataset.uploadStatus = "error";
    li.className = "flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 dark:bg-red-900/30 text-sm text-red-700 dark:text-red-300";

    const message = document.createElement("span");
    message.setAttribute("role", "alert");
    message.textContent = `Invalid file: ${file.name}`;
    li.appendChild(message);

    const removeBtn = document.createElement("button");
    removeBtn.type = "button";
    removeBtn.dataset.action = "dropzone#removeFile";
    removeBtn.textContent = "Remove upload";
    li.appendChild(removeBtn);

    this.listTarget.appendChild(li);
    this.listTarget.classList.remove("hidden");
    this._publishChatSourceState();
  }

  _dequeueNext() {
    if (this.activeUploads.length >= this.parallelLimitValue || this.uploadQueue.length === 0) {
      return;
    }

    const file = this.uploadQueue.shift();
    this._uploadFile(file);
  }

  _uploadFile(file) {
    // Update status to uploading
    const entry = [...this.listTarget.querySelectorAll("[data-file-name]")].find(row => row.dataset.fileName === file.name);
    if (entry) {
      entry.dataset.uploadStatus = "uploading";
      const statusMark = entry.querySelector(".status-mark");
      if (statusMark) {
        statusMark.className = "status-mark flex-shrink-0 w-4 h-4 rounded-full border-2 border-blue-500 animate-pulse";
      }
    }

    this.activeUploads.push(file);
    this._publishChatSourceState();

    const xhr = new XMLHttpRequest();
    this.xhrsByFileName.set(file.name, xhr);

    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && entry) {
        const percent = Math.round((event.loaded / event.total) * 100);
        // Could add progress bar here if needed
      }
    };

    xhr.onload = () => this._finishUpload(file, xhr.status >= 200 && xhr.status < 300 ? "success" : "error", xhr);
    xhr.onerror = xhr.onabort = () => this._finishUpload(file, "error", xhr);

    const formData = new FormData();
    // Add document parameters - title is required by the controller
    formData.append("document[title]", file.name);
    formData.append("document[file]", file);
    formData.append("document[upload_id]", this.uploadIdsByFileName.get(file.name));
    if (this.hasAccountIdValue && this.accountIdValue.trim()) {
      formData.append("document[account_id]", this.accountIdValue);
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || "";
    xhr.open("POST", this.urlValue, true);
    xhr.setRequestHeader("X-CSRF-Token", csrfToken);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.send(formData);
  }

  _finishUpload(file, status, xhr) {
    if (this.xhrsByFileName.get(file.name) !== xhr) return;
    this.xhrsByFileName.delete(file.name);
    this.activeUploads = this.activeUploads.filter(active => active.name !== file.name);
    const entry = [...this.listTarget.querySelectorAll("[data-file-name]")].find(row => row.dataset.fileName === file.name);
    entry?.remove();
    this._renderFileEntry(file, status);
    this._dequeueNext();
    this._publishChatSourceState();
  }

  _publishChatSourceState() {
    if (!this.element.isConnected) return;
    this.dispatch("state", { detail: {
      pending: this.activeUploads.length + this.uploadQueue.length,
      failed: Boolean(this.listTarget.querySelector("[data-upload-status='error']")),
      dirty: this.listTarget.children.length > 0
    } });
  }

  resetChatDraft(event) {
    if (!event.detail.root.contains(this.element)) return;
    this._abortAllUploads();
    this.filesByName.clear();
    this.uploadIdsByFileName.clear();
    this.listTarget.replaceChildren();
    this.listTarget.classList.add("hidden");
    this.inputTarget.value = "";
    this._publishChatSourceState();
  }

  removeFile(e) {
    e.stopPropagation();
    const entry = e.currentTarget.closest("[data-file-name]");
    if (!entry) return;
    const fileName = entry.dataset.fileName;

    const xhr = this.xhrsByFileName.get(fileName);
    this.xhrsByFileName.delete(fileName);
    this.activeUploads = this.activeUploads.filter((f) => f.name !== fileName);
    this.uploadQueue = this.uploadQueue.filter((f) => f.name !== fileName);
    this.filesByName.delete(fileName);
    this.uploadIdsByFileName.delete(fileName);
    if (xhr) {
      xhr.onload = xhr.onerror = xhr.onabort = null;
      xhr.abort();
    }

    entry.remove();
    if (this.listTarget.children.length === 0) {
      this.listTarget.classList.add("hidden");
    }
    this._dequeueNext();
    this._publishChatSourceState();
  }

  retryFile(e) {
    e.stopPropagation();
    if (!this.element.isConnected || this.element.closest("[inert]")) return;
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
    this._publishChatSourceState();
  }

  _abortAllUploads() {
    const requests = [...this.xhrsByFileName.values()];
    this.xhrsByFileName.clear();
    this.activeUploads = [];
    this.uploadQueue = [];
    for (const xhr of requests) {
      xhr.onload = xhr.onerror = xhr.onabort = null;
      xhr.abort();
    }
  }
}
