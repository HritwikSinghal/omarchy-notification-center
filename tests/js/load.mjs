// Loads one of the plugin's `.pragma library` JS files the way QML would: its
// top-level functions and vars, in a context of their own. Objects it returns
// come from that context, so compare them with JSON (see `plain`), not with
// deepStrictEqual, whose prototype check would fail across contexts.
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import path from "node:path"
import vm from "node:vm"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")

export function loadLibrary(name) {
  const file = path.join(root, name)
  const source = readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
  const context = vm.createContext({})
  vm.runInContext(source, context, { filename: file })
  return context
}

export const plain = (value) => JSON.parse(JSON.stringify(value))
