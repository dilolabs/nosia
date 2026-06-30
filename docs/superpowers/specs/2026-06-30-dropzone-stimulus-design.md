# Dropzone.js → Pure Stimulus Design

**Date:** 2026-06-30  
**Status:** Approved  
**Scope:** Replace Dropzone.js library with pure Stimulus controller for file uploads on dashboard and documents index pages.

---

## Problem Statement

The current implementation uses the Dropzone.js library (v6.0.0) wrapped in a Stimulus controller to handle file uploads. This adds an external dependency (~50KB minified) for functionality that can be implemented more simply with native browser APIs and Stimulus.

**Current setup:**
- `app/javascript/controllers/dropzone_controller.js` — wraps Dropzone.js
- `config/importmap.rb:8` — pins `"dropzone"` 
- Two views use the controller: dashboard show (full UI) and documents index (minimal)

---

## Design Decisions

### 1. Single Reusable Controller (Approach A)

**Decision:** One Stimulus controller with data attributes for customization, replacing both page variants.

**Rationale:**
- Both pages share identical upload logic (POST to `/sources/documents`, same file validation)
- Different visual presentation (dashboard: full UI with status marks; documents index: minimal list)
- Single source of truth prevents drift between variants
- Data attributes keep markup clean and self-documenting

**Alternatives considered:**
- **Two separate controllers:** Simpler API but duplicates logic, harder to maintain
- **Turbo Streams for feedback:** Cleaner UX but adds server complexity for marginal benefit at this scale

---

### 2. Pure Stimulus Implementation

**Decision:** Remove Dropzone.js entirely. Use native `dragenter`/`dragover`/`drop` events + hidden `<input type="file">`.

**Rationale:**
- Browser APIs handle drag-and-drop natively since 2015
- `fetch()` with `XMLHttpRequest.upload.onprogress` provides upload tracking without library overhead
- Eliminates ~50KB dependency, reduces bundle size, removes potential version conflicts
- Aligns with Rails/Hotwire philosophy of leveraging native browser capabilities

**Key implementation details:**
- File input: `<input type="file" multiple class="hidden" data-dropzone-target="input">`
- Drag events: `dragenter`, `dragover`, `drop` on container element
- Upload: `fetch()` with FormData, CSRF token in headers, progress via XHR upload event
- Parallel uploads: limit to 5 concurrent (matches current Dropzone config)

---

### 3. Two Visual Variants via Data Attribute

**Decision:** Controller supports `"dashboard"` and `"minimal"` variants via `data-variant` attribute.

**Dashboard variant (`data-variant="dashboard"`):**
```html
<div data-controller="dropzone" data-variant="dashboard">
  <div data-dropzone-target="container" class="...">
    <input type="file" multiple hidden data-dropzone-target="input">
    <div class="icon">...</div>
    <p>Add any document</p>
    <p class="text-sm text-neutral-500">Click or drag'n'drop files here to upload</p>
    <ul data-dropzone-target="list" class="hidden mt-6"></ul>
  </div>
</div>
```

**Minimal variant (`data-variant="minimal"`):**
```html
<div data-controller="dropzone" data-variant="minimal">
  <input type="file" multiple hidden data-dropzone-target="input">
  <p class="text-sm text-neutral-500">Drop files here or click to browse</p>
  <ul data-dropzone-target="list" class="mt-4"></ul>
</div>
```

**File entry markup (dashboard):**
```html
<li data-file-name="document.pdf" class="flex items-center gap-2 px-3 py-2 rounded-lg bg-neutral-50 dark:bg-neutral-700/50 text-sm">
  <span class="status-mark flex-shrink-0 w-4 h-4 rounded-full border-2 border-neutral-300"></span>
  <span class="file-name truncate flex-1 text-neutral-700 dark:text-neutral-200">document.pdf</span>
  <button data-action="dropzone#removeFile" class="...">✕</button>
</li>
```

---

### 4. Upload Flow & Status Tracking

**Decision:** Client-side status tracking with server response feedback. No polling or Turbo Streams needed.

**Flow:**
1. **Idle** → User drags file over container or clicks dropzone area
2. **Active (dragging)** → Visual highlight on container (`border-blue-500`, `bg-blue-50`)
3. **Uploading** → File added to list, status mark shows spinner/progress
4. **Success** → Green checkmark icon, file name stays in list
5. **Error** → Red X icon, "Remove & Retry" button appears

**Upload implementation:**
```javascript
const xhr = new XMLHttpRequest();
xhr.upload.onprogress = (event) => {
  if (event.lengthComputable) {
    const percent = (event.loaded / event.total) * 100;
    this._updateProgress(entry, percent);
  }
};
xhr.open('POST', url, true);
xhr.setRequestHeader('X-CSRF-Token', csrfToken);
xhr.send(formData);
```

**Parallel upload limit:** Track active uploads in `this.activeUploads` array. When a file completes, dequeue next from queue if available (max 5 concurrent).

---

### 5. Validation & Error Handling

**Decision:** Client-side validation before upload + server error handling after response.

**Client-side checks (before upload):**
- **File size:** `file.size > maxFileSize * 1024 * 1024` → show inline error, don't start upload
- **File type:** Use `<input accept="...">` for browser filtering + validate MIME types in controller

**Server response handling:**
- **2xx (success):** Mark entry as success, show green checkmark
- **Non-2xx (error):** Parse response body for error message, mark entry as error with red X and "Remove & Retry" button
- **Network failure:** Show generic error message, retry button

**Retry behavior:** Clicking "Remove & Retry" removes the failed entry from Dropzone's internal tracking and re-triggers upload for that file.

---

### 6. CSRF Token Handling

**Decision:** Read from `<meta name="csrf-token">` and include in fetch headers (matches current implementation).

```javascript
const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
// Include in XHR:
xhr.setRequestHeader('X-CSRF-Token', csrfToken);
```

---

## Files to Change

| File | Action | Notes |
|------|--------|-------|
| `app/javascript/controllers/dropzone_controller.js` | **REPLACE** | New pure Stimulus implementation (~200 lines) |
| `config/importmap.rb` | **EDIT** | Remove line 8: `pin "dropzone" # @6.0.0` |
| `app/views/dashboards/show.html.erb` | **UPDATE** | Use new controller markup with `data-variant="dashboard"` |
| `app/views/sources/documents/index.html.erb` | **UPDATE** | Use new controller markup with `data-variant="minimal"` |

---

## Files to Remove

None. The Dropzone.js library is loaded via importmap, not a separate file. Removing the pin from `importmap.rb` is sufficient.

---

## Testing Strategy

**Manual testing checklist:**
1. Dashboard page: drag files into dropzone → verify highlight, file list appears, upload starts
2. Dashboard page: click dropzone area → file picker opens, selected files upload
3. Dashboard page: remove a file mid-upload → XHR aborts, entry removed from list
4. Dashboard page: drop file that's too large (>512MB) → inline error shown, no upload attempted
5. Dashboard page: drop non-PDF/DOCX/text file → rejected by browser (accept attribute), or client-side validation
6. Documents index page: same behaviors as above but with minimal UI variant
7. Network failure simulation → verify error state and retry button works

**Automated tests:** None added in this iteration. The existing test suite should continue to pass without changes (upload endpoint behavior unchanged).

---

## Migration Notes

- **No database changes** — upload endpoint (`POST /sources/documents`) remains identical
- **No API contract changes** — client sends same FormData structure, server receives same params
- **Backward compatible** — if needed, can revert by re-adding Dropzone.js pin and restoring old controller (though it would be removed from repo)

---

## Open Questions

None identified. All design decisions resolved during brainstorming session.
