const encoder = new TextEncoder()
const bytes = (value) => encoder.encode(value).length
const markdown = (name) => name.slice(-3).toLowerCase() === ".md"

function validComponent(name, limits) {
  return name && !/^\p{White_Space}+$/u.test(name) && !/[\\\p{Cc}\p{Cs}]/u.test(name) &&
    ![".", "..", ".obsidian"].includes(name) && !/^[a-z]:/i.test(name) && bytes(name) <= limits.componentBytes
}

// Use only browser-supplied names and sizes. Never open a file during preview.
export function previewFolder(files, limits) {
  const entries = new Map()
  const folders = new Set([""])
  const ignored = { obsidian: 0, other: 0 }
  let root, total = 0

  for (const file of files) {
    const [name, ...components] = file.webkitRelativePath.normalize("NFC").split("/")
    if (!components.length || !validComponent(name, limits) || (root !== undefined && root !== name)) {
      return { error: "invalid_root_name" }
    }
    root = name
    const leaf = components.at(-1)
    if (components.slice(0, -1).includes(".obsidian")) {
      ignored.obsidian++
    } else if (!markdown(leaf)) {
      ignored.other++
    } else {
      const path = components.join("/")
      if (bytes(path) > limits.pathBytes || !components.every((name) => validComponent(name, limits))) return { error: "invalid_path" }
      if (components.length - 1 > limits.depth) return { error: "depth_limit_exceeded" }
      if (entries.has(path)) return { error: "duplicate_path" }
      if (file.size > limits.fileBytes) return { error: "invalid_file_size" }
      if (limits.batchBytes === 0 || file.size > limits.batchBytes) return { error: "transport_file_size" }

      entries.set(path, file)
      total += file.size
      if (entries.size > limits.files) return { error: "invalid_file_count" }
      if (total > limits.totalBytes) return { error: "total_size_exceeded" }

      let folder = ""
      for (const part of components.slice(0, -1)) {
        folder = folder ? `${folder}/${part}` : part
        folders.add(folder)
      }
      if (folders.size > limits.folders) return { error: "folder_limit_exceeded" }
    }
  }

  if (!entries.size) return { error: "invalid_file_count" }
  if (Object.values(ignored).some((count) => count > limits.ignoredCount)) return { error: "invalid_ignored_counts" }
  if (Array.from(entries.keys()).some((path) => folders.has(path))) return { error: "path_collision" }

  return { root, entries, folders: folders.size, ignored }
}

export function fillMessage(template, values) {
  return template.replace(/%\{(\w+)\}/g, (token, key) => Object.hasOwn(values, key) ? values[key] : token)
}
