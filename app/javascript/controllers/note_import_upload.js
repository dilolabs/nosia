export class UploadRejection extends Error {
  constructor(response, detail) {
    super(detail?.message)
    this.status = response.status
    this.code = detail?.error
  }
}

export async function uploadFolder(url, selection, limits, signal, progress) {
  const { key, root, entries, ignored } = selection
  const receipt = await post(url, {
    confirmation_key: key, root_name: root, ignored_counts: ignored,
    files: Array.from(entries, ([path, file]) => ({ path, size: file.size }))
  }, signal)

  if (receipt.status === "uploading" && receipt.uploaded_count !== entries.size) {
    for (const batch of batches(entries, limits)) {
      const ack = await post(receipt.batch_url, batch, signal)
      progress(ack.uploaded_count, ack.total)
    }
  }
  if (receipt.status === "uploading" || receipt.status === "sealed") {
    await post(receipt.seal_url, {}, signal)
  }
  return receipt.status_url
}

function* batches(entries, { batchFiles, batchBytes }) {
  let form = new FormData(), count = 0, bytes = 0
  for (const [path, file] of entries) {
    if (count >= batchFiles || bytes + file.size > batchBytes) {
      yield form
      form = new FormData()
      count = bytes = 0
    }
    form.append("entries[][path]", path)
    form.append("entries[][file]", file, "note.md") // The server only needs the logical path.
    count++
    bytes += file.size
  }
  if (count) yield form
}

async function post(url, body, signal) {
  signal.throwIfAborted()
  if (new URL(url, location.href).origin !== location.origin) throw new TypeError()

  const headers = { Accept: "application/json" }
  const token = document.querySelector("meta[name=csrf-token]")?.content
  if (token) headers["X-CSRF-Token"] = token
  if (!(body instanceof FormData)) {
    headers["Content-Type"] = "application/json"
    body = JSON.stringify(body)
  }
  const response = await fetch(url, {
    method: "POST", headers, body, signal, credentials: "same-origin", cache: "no-store", redirect: "error"
  })
  if (!response.ok) {
    const detail = await response.json().catch(() => null)
    throw new UploadRejection(response, detail)
  }
  return response.json()
}
