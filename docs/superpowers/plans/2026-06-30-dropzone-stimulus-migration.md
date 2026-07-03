# Dropzone.js → Pure Stimulus Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Dropzone.js library dependency with a pure Stimulus controller that handles drag-and-drop, file upload tracking, and status feedback — eliminating ~50KB of external JS while maintaining identical functionality across dashboard and documents index pages.

**Architecture:** Single Stimulus controller (`dropzone_controller.js`) with data attributes for customization. Native browser APIs handle drag-and-drop events; `XMLHttpRequest.upload.onprogress` provides upload progress tracking without library overhead. Two visual variants (dashboard/minimal) driven by `data-variant` attribute.

**Tech Stack:** Ruby on Rails 8 · Stimulus 3.2.2 · Hotwire · Tailwind CSS · Importmap (no npm build step needed)

---

## File Structure

### Files to Create
| Path | Purpose |
|------|---------|
| `app/javascript/controllers/dropzone_controller.js` | NEW — Pure Stimulus implementation (~200 lines) |

### Files to Modify
| Path | Change |
|------|--------|
| `config/importmap.rb:8` | Remove `pin "dropzone" # @6.0.0` |
| `app/views/dashboards/show.html.erb:11-29` | Update markup to use new controller with `data-variant="dashboard"` |
| `app/views/sources/documents/index.html.erb:6` | Update markup to use new controller with `data-variant="minimal"` |

### Files to Remove
None — Dropzone.js is loaded via importmap, not a separate file. Removing the pin is sufficient.

---

## Implementation Tasks

### Task 1: Write New Stimulus Controller (Core Upload Logic)

**Files:**
- Create: `app/javascript/controllers/dropzone_controller.js`

**Purpose:** Implement core upload logic — drag-and-drop handling, file selection, XHR uploads with progress tracking, parallel upload limiting.

```javascript
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["container", "input", "list"];
  static values = {
    url: String,
    maxFileSize: Number, // in MB
    acceptedFiles: String, // comma-separated MIME types
    multiple: Boolean,
    variant: String, // "dashboard" or "minimal"
    parallelLimit: { type: Number, default: 5 }
  };

  connect() {
    this.activeUploads = [];
    this.uploadQueue = [];
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
    files.forEach((file) => {
      if (this._validateFile(file)) {
        this.uploadQueue.push(file);
        this._renderFileEntry(file, "pending");
        this._dequeueNext();
      } else {
        this._showValidationError(file);
      }
    });
  }

  _validateFile(file) {
    // Check file size
    const maxSizeBytes = this.maxFileSizeValue * 1024 * 1024;
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
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && entry) {
        const percent = Math.round((event.loaded / event.total) * 100);
        // Could add progress bar here if needed
      }
    };

    xhr.onload = () => {
      this.activeUploads = this.activeUploads.filter((f) => f !== file);
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
      this.activeUploads = this.activeUploads.filter((f) => f !== file);
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
```

**Notes:**
- `removeFile` and `_abortAllUploads` are complete in Task 1 — Task 2 adds the supporting Maps (`filesByName`, `xhrsByFileName`) but does not replace these methods.
- Parallel upload limiting uses a simple queue with active count tracking.
- Progress tracking via `xhr.upload.onprogress` is minimal (just computes percentage) but can be expanded if needed.

**Verification:** No automated tests for JS currently exist. Manual testing required after all tasks complete.

---

### Task 2: Fix Retry Logic & Edge Cases

**Files:**
- Modify: `app/javascript/controllers/dropzone_controller.js`

**Purpose:** Complete the retry functionality and handle edge cases properly.

**Changes needed:**

1. **Store File objects by name** — Add a Map to track files:
```javascript
connect() {
  this.activeUploads = [];
  this.uploadQueue = [];
  this.filesByName = new Map(); // fileName → File object
  this._bindEvents();
}

// In _processFiles, before pushing to queue:
this.filesByName.set(file.name, file);

// In retryFile:
retryFile(e) {
  e.stopPropagation();
  const entry = e.currentTarget.closest("[data-file-name]");
  if (!entry) return;
  const fileName = entry.dataset.fileName;
  const file = this.filesByName.get(fileName);
  if (file) {
    // Remove error styling from old entry
    entry.remove();
    // Re-render as pending and re-queue
    this._renderFileEntry(file, "pending");
    this.uploadQueue.push(file);
    this._dequeueNext();
  }
}
```

2. **Track XHRs for proper abort** — Add Map to track active XHRs:
```javascript
connect() {
  this.activeUploads = [];
  this.uploadQueue = [];
  this.filesByName = new Map();
  this.xhrsByFileName = new Map(); // fileName → XHR object
  this._bindEvents();
}

// In _uploadFile, before xhr.send:
this.xhrsByFileName.set(file.name, xhr);

// In removeFile:
removeFile(e) {
  e.stopPropagation();
  const entry = e.currentTarget.closest("[data-file-name]");
  if (!entry) return;
  const fileName = entry.dataset.fileName;
  
  // Abort XHR if active
  const xhr = this.xhrsByFileName.get(fileName);
  if (xhr) {
    xhr.abort();
    this.xhrsByFileName.delete(fileName);
  }
  
  // Remove from queues
  this.activeUploads = this.activeUploads.filter((f) => f.name !== fileName);
  this.uploadQueue = this.uploadQueue.filter((f) => f.name !== fileName);
  
  entry.remove();
  if (this.listTarget.children.length === 0) {
    this.listTarget.classList.add("hidden");
  }
}

// In _uploadFile onload/onerror:
xhr.onload = () => {
  this.activeUploads = this.activeUploads.filter((f) => f.name !== file.name);
  this.xhrsByFileName.delete(file.name);
  // ... rest of success/error handling
};
```

3. **Handle empty drop / no files** — Already handled by `_processFiles` being called with empty array (no-op).

4. **Prevent duplicate uploads** — Add check in `_processFiles`:
```javascript
_processFiles(files) {
  const uniqueFiles = files.filter(
    (file) => !this.filesByName.has(file.name) && !this.uploadQueue.find((f) => f.name === file.name)
  );
  // ... rest of processing
}
```

**Verification:** Manual testing — retry a failed upload, verify it restarts. Try uploading same file twice quickly, verify no duplicates appear.

---

### Task 3: Remove Dropzone.js from Importmap

**Files:**
- Modify: `config/importmap.rb:8`

**Action:** Delete line 8 entirely (or comment it out if you want to keep history):

```ruby
# Before:
pin "dropzone" # @6.0.0

# After:
# (line removed)
```

**Verification:** Run `bin/importmap audit` to ensure no broken pins. No other files reference Dropzone.js in this codebase (verified via grep).

---

### Task 4: Update Dashboard Show View Markup

**Files:**
- Modify: `app/views/dashboards/show.html.erb:11-29`

**Current markup (lines 11-29):**
```erb
<div class="mt-3 lg:mt-12 flex justify-center">
  <div class="w-full bg-white dark:bg-neutral-800 shadow-sm rounded-3xl border n-main-border">
    <div data-controller="dropzone" data-action="dragenter->dropzone#highlight dragover->dropzone#highlight dragleave->dropzone#unhighlight drop->dropzone#drop click->dropzone#pick"
      class="group relative flex-wrap m-6 sm:m-8 p-3 sm:p-6 md:py-14 rounded-xl text-center transition-all border-2 border-dashed n-main-border n-main-hover n-main-focus"
      >
      <input type="file" multiple class="hidden" data-dropzone-target="input">
      <div class="mx-auto mb-4 h-12 w-12 rounded-2xl ring-1 ring-neutral-200/70 flex items-center justify-center
                  group-data-[active=true]:ring-neutral-300 transition">
        <%= inline_svg_tag "svg/download.svg", class: "h-6 w-6 text-neutral-500 dark:text-neutral-400" %>
      </div>

      <p class="text-base sm:text-lg font-semibold text-neutral-800 dark:text-white">Add any document</p>
      <p class="mt-1 text-sm text-neutral-500 dark:text-neutral-400">Click or drag'n'drop files here to upload</p>
      <p class="mt-2 text-xs text-neutral-400 dark:text-neutral-500">PDF, PNG, JPG, DOCX · max 512&nbsp;MB</p>

      <div class="pointer-events-none absolute inset-0 rounded-2xl ring-8 ring-transparent
                  group-data-[active=true]:ring-neutral-100 transition"></div>

      <ul class="mt-6 max-w-md mx-auto space-y-2 text-left hidden" data-dropzone-target="list"></ul>
    </div>
  </div>
</div>
```

**New markup:**
```erb
<div class="mt-3 lg:mt-12 flex justify-center">
  <div class="w-full bg-white dark:bg-neutral-800 shadow-sm rounded-3xl border n-main-border">
    <div data-controller="dropzone" 
         data-variant="dashboard"
         data-url-value="/sources/documents"
         data-max-file-size-value="512"
         data-accepted-files-value="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/*,image/png,image/jpeg"
         class="relative m-6 sm:m-8 p-3 sm:p-6 md:py-14 rounded-xl text-center">
      
      <div data-dropzone-target="container" 
           class="group relative flex-wrap p-3 sm:p-6 md:py-14 rounded-xl text-center transition-all border-2 border-dashed n-main-border n-main-hover n-main-focus"
           data-active="false">
        
        <input type="file" multiple 
               accept="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/*,image/png,image/jpeg"
               class="hidden" 
               data-dropzone-target="input">
        
        <div class="mx-auto mb-4 h-12 w-12 rounded-2xl ring-1 ring-neutral-200/70 flex items-center justify-center
                    group-data-[active=true]:ring-neutral-300 transition">
          <%= inline_svg_tag "svg/download.svg", class: "h-6 w-6 text-neutral-500 dark:text-neutral-400" %>
        </div>

        <p class="text-base sm:text-lg font-semibold text-neutral-800 dark:text-white">Add any document</p>
        <p class="mt-1 text-sm text-neutral-500 dark:text-neutral-400">Click or drag'n'drop files here to upload</p>
        <p class="mt-2 text-xs text-neutral-400 dark:text-neutral-500">PDF, PNG, JPG, DOCX · max 512&nbsp;MB</p>

        <div class="pointer-events-none absolute inset-0 rounded-2xl ring-8 ring-transparent
                    group-data-[active=true]:ring-neutral-100 transition"></div>
      </div>

      <ul data-dropzone-target="list" 
          class="mt-6 max-w-md mx-auto space-y-2 text-left hidden">
      </ul>
    </div>
  </div>
</div>
```

**Key changes:**
1. Added `data-variant="dashboard"` to controller element
2. Added `data-url-value`, `data-max-file-size-value`, `data-accepted-files-value` attributes
3. Wrapped inner content in new `<div data-dropzone-target="container">` for drag events (separate from outer wrapper)
4. Removed inline event handlers (`dragenter->dropzone#highlight` etc.) — controller handles these internally via `_bindEvents()`
5. Added `accept` attribute to file input for browser-level filtering
6. Kept `list` target inside the container div (matches spec, file list renders within the card)

**Note:** The `<ul>` remains inside the container div per the design spec. Drag events on the list area bubble up to the container, so dropping files on the existing file list still triggers upload correctly.

**Verification:** Visit dashboard page, drag files into dropzone, verify highlight appears on hover, files upload and show in list with status marks.

---

### Task 5: Update Documents Index View Markup

**Files:**
- Modify: `app/views/sources/documents/index.html.erb:6`

**Current markup (line 6):**
```erb
<div data-controller="dropzone" class="mt-2 !flex items-stretch justify-center dropzone"></div>
```

**New markup:**
```erb
<div data-controller="dropzone" 
     data-variant="minimal"
     data-url-value="/sources/documents"
     data-max-file-size-value="512"
     class="mt-2">
  <div data-dropzone-target="container" 
       class="border-2 border-dashed p-4 text-center cursor-pointer hover:border-blue-500 transition rounded-lg bg-neutral-50 dark:bg-neutral-800/50">
    <input type="file" multiple 
           accept="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/*,image/png,image/jpeg"
           class="hidden" 
           data-dropzone-target="input">
    <p class="text-sm text-neutral-500 dark:text-neutral-400">Drop files here or click to browse</p>
  </div>
  <ul data-dropzone-target="list" class="mt-4 space-y-1"></ul>
</div>
```

**Key changes:**
1. Added `data-variant="minimal"` 
2. Added configuration attributes (`data-url-value`, `data-max-file-size-value`)
3. Added container div with simpler styling (no icon, shorter text)
4. Added file input with accept attribute
5. Added list target for file entries

**Verification:** Visit documents index page, drag files into dropzone, verify minimal UI works correctly (simpler styling, no remove button on entries).

---

### Task 6: Manual Testing & Verification

**Purpose:** Verify all functionality works end-to-end across both variants.

**Test checklist:**

1. **Dashboard variant:**
   - [ ] Drag files into dropzone → highlight appears on container
   - [ ] Click dropzone area → file picker opens
   - [ ] Select multiple files → all appear in list with pending status (gray border)
   - [ ] Uploads start automatically, status changes to uploading (blue pulse)
   - [ ] Successful upload → green checkmark appears
   - [ ] Failed upload → red X appears, "Retry" button shows
   - [ ] Click "Remove" on a file → entry removed from list
   - [ ] Remove file mid-upload → XHR aborts, entry disappears
   - [ ] Drop file >512MB → inline error shown, no upload attempted
   - [ ] Drop invalid file type (if browser allows) → client-side validation rejects it
   - [ ] Try uploading same file twice quickly → no duplicates appear

2. **Minimal variant:**
   - [ ] Drag files into dropzone → highlight appears on container
   - [ ] Click dropzone area → file picker opens
   - [ ] Select multiple files → all appear in list with pending status
   - [ ] Uploads start automatically, status changes to uploading
   - [ ] Successful upload → green checkmark appears
   - [ ] Failed upload → red X appears (no retry button in minimal variant)
   - [ ] Remove file mid-upload → entry disappears

3. **Cross-cutting:**
   - [ ] Network failure simulation (disable network in DevTools) → error state shows, retry works
   - [ ] Page reload during upload → uploads cancel (controller disconnects)
   - [ ] Dark mode → styling works correctly in both variants
   - [ ] Mobile/touch devices → click-to-browse works, drag-and-drop not applicable

4. **Regression:**
   - [ ] Existing tests still pass: `bin/rails test`
   - [ ] Rubocop passes: `bundle exec rubocop`
   - [ ] No console errors in browser DevTools

**Commands to run:**
```bash
# Run Rails test suite
bin/rails test

# Run Rubocop
bundle exec rubocop

# Check importmap (optional, since we removed a pin)
bin/importmap audit
```

---

## Migration Notes

- **No database changes** — upload endpoint (`POST /sources/documents`) remains identical
- **No API contract changes** — client sends same FormData structure (`document[file]`), server receives same params
- **Backward compatible** — if needed, can revert by re-adding Dropzone.js pin and restoring old controller (though it would be removed from repo)

---

## Open Questions

None identified. All design decisions resolved during brainstorming session.
