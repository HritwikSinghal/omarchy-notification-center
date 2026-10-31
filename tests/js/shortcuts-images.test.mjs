// Shortcuts.js (the footer key table) and Images.js (matching rows to images).
import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLibrary, plain } from "./load.mjs"

const S = loadLibrary("Shortcuts.js")
const I = loadLibrary("Images.js")
const key = (letter) => letter.charCodeAt(0)

test("each Ctrl shortcut maps to its action, and nothing else does", () => {
  const cases = [
    ["M", false, "markRead"], ["D", false, "closeAll"], ["L", false, "clear"],
    ["E", false, "expandAll"], ["E", true, "collapseAll"], ["Z", false, "undo"],
  ]
  for (const [letter, shift, action] of cases)
    assert.equal(S.actionFor(key(letter), true, shift, false), action, letter + (shift ? "+Shift" : ""))
  assert.equal(S.actionFor(key("M"), true, true, false), "", "Ctrl+Shift+M")
  assert.equal(S.actionFor(key("E"), true, false, true), "", "with Alt or Meta")
  assert.equal(S.actionFor(key("M"), false, false, false), "", "without Ctrl")
  assert.equal(S.actionFor(key("A"), true, false, false), "", "Ctrl+A stays select-all")
})

test("no two actions share a key, and every label names its key", () => {
  const seen = new Set()
  for (const [name, action] of Object.entries(S.actions)) {
    const combo = action.key + (action.shift ? "+shift" : "")
    assert.ok(!seen.has(combo), name + " reuses " + combo)
    seen.add(combo)
    assert.match(action.label, new RegExp("^Ctrl\\+" + (action.shift ? "Shift\\+" : "") + action.key + "$"), name)
  }
})

// ---- Images.js

const DIR = "file:///home/u/.cache/gabodev.notification-center/images/"
const img = (c) => DIR + c.repeat(40) + ".png"

test("safeImage accepts only an image named by its hash in the helper's cache", () => {
  assert.equal(I.safeImage(img("a")), img("a"))
  assert.equal(I.safeImage(DIR + "0123456789abcdef0123456789abcdef01234567.webp"),
    DIR + "0123456789abcdef0123456789abcdef01234567.webp")
  const dotted = "file:///home/..u/.cache/gabodev.notification-center/images/" + "a".repeat(40) + ".png"
  assert.equal(I.safeImage(dotted), dotted, "a directory merely starting with dots is fine")
  for (const bad of [
    "file:///home/u/../../etc/gabodev.notification-center/images/" + "a".repeat(40) + ".png",
    "file:///home/u/./gabodev.notification-center/images/" + "a".repeat(40) + ".png",
    "file:///home//u/gabodev.notification-center/images/" + "a".repeat(40) + ".png",
    "file:///home/u x/gabodev.notification-center/images/" + "a".repeat(40) + ".png",
    img("a") + " ",
    img("a") + ".svg",
    DIR + "abc.png",
    DIR + "A".repeat(40) + ".png",
    "file://host/x/gabodev.notification-center/images/" + "a".repeat(40) + ".png",
    "https://tracker.example/" + img("a"),
    "file:///etc/passwd", "", null,
  ])
    assert.equal(I.safeImage(bad), "", String(bad))
})

test("parse keeps valid records, at most LIMIT of them", () => {
  const entries = I.parse(JSON.stringify([
    { id: 3, app: "tidal-hifi", ts: 1000, image: img("a") },
    { id: 4, app: "x", ts: 1000, image: "file:///etc/passwd" },
    { id: 0, app: "x", ts: 1000, image: img("a") },
    { id: 5, app: "x", ts: "never", image: img("a") },
  ]))
  assert.deepEqual(plain(entries).map((e) => e.id), [3], "bad image, id or ts dropped")
  assert.equal(I.parse("junk").length, 0)
  assert.equal(I.parse('{"id":1}').length, 0)
  const many = Array.from({ length: I.LIMIT + 5 }, (_, i) => ({ id: i + 1, app: "a", ts: 1, image: img("a") }))
  assert.equal(I.parse(JSON.stringify(many)).length, I.LIMIT)
})

test("add puts the new record first, keeps LIMIT, and refuses an unsafe one", () => {
  const full = Array.from({ length: I.LIMIT }, (_, i) => ({ id: i + 1, app: "a", ts: 1, image: img("a") }))
  const out = I.add(full, { id: 999, app: "a", ts: 2, image: img("b") })
  assert.equal(out.length, I.LIMIT)
  assert.equal(out[0].id, 999)
  assert.equal(out[1].id, 1)
  assert.equal(I.add([], { id: 1, ts: 1, image: "file:///etc/passwd" }).length, 0)
})

test("lookup matches a row by id and app, within WINDOW seconds either side", () => {
  const tidal = { id: 3, app: "tidal-hifi", ts: 1000, image: img("a") }
  const mail = { id: 3, app: "Mail", ts: 1000, image: img("c") }
  const entries = [mail, tidal]
  assert.equal(I.lookup(entries, { originalId: "3", app: "Tidal-HiFi", ts: 1010 }), img("a"))
  assert.equal(I.lookup(entries, { originalId: "3", app: "Tidal HiFi", ts: 1000 }), img("a"), "punctuation ignored")
  assert.equal(I.lookup(entries, { originalId: "3", app: "mail", ts: 1000 }), img("c"))
  assert.equal(I.lookup(entries, { originalId: "9", app: "tidal-hifi", ts: 1000 }), "")
  assert.equal(I.lookup([tidal], { originalId: 3, app: "tidal-hifi", ts: 1000 + I.WINDOW }), img("a"), "edge of window")
  assert.equal(I.lookup([tidal], { originalId: 3, app: "tidal-hifi", ts: 1000 + I.WINDOW + 1 }), "", "too late")
  assert.equal(I.lookup([tidal], { originalId: 3, app: "tidal-hifi", ts: 1000 - I.WINDOW - 1 }), "", "too early")
  assert.equal(I.lookup([tidal], { app: "tidal-hifi", ts: 1000 }), "", "a row without an id")
})

test("after a restart reuses an id, lookup takes the entry nearest in time", () => {
  const older = { id: 3, app: "tidal-hifi", ts: 1000, image: img("a") }
  const newer = { id: 3, app: "tidal-hifi", ts: 1050, image: img("b") }
  for (const entries of [[newer, older], [older, newer]])
    assert.equal(I.lookup(entries, { originalId: 3, app: "tidal-hifi", ts: 1045 }), img("b"))
})
