// History.js: the panel's and the bell's view state over Omarchy's history.
import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLibrary, plain } from "./load.mjs"

const H = loadLibrary("History.js")
const now = H.nowSeconds()
const DAY = 24 * 60 * 60
const empty = () => ({ lastSeen: 0, lastOpened: 0, clearedAt: 0, hidden: {} })
const keys = (rows) => rows.map((row) => row.key).join(" ")

// Rows newest first, like Omarchy's history: A has 8, B 3, C 2.
function sample() {
  const rows = []
  for (let i = 0; i < 8; i++) rows.push({ key: "a" + i, app: "A", ts: now - 10 - i, closed_ts: now - 5 - i })
  for (let i = 0; i < 3; i++) rows.push({ key: "b" + i, app: "B", ts: now - 30 - i, closed_ts: now - 25 - i })
  for (let i = 0; i < 2; i++) rows.push({ key: "c" + i, app: "C", ts: now - 50 - i, closed_ts: now - 45 - i })
  return rows
}

// ---- config file

test("config round trip keeps every field and rejects junk", () => {
  const state = { lastSeen: 1, lastOpened: now - 100, clearedAt: 2, hidden: { k1: now } }
  const back = H.parseConfig(H.serialiseConfig(state), now)
  assert.equal(back.lastSeen, 1)
  assert.equal(back.lastOpened, now - 100)
  assert.equal(back.clearedAt, 2)
  assert.deepEqual(Object.keys(back.hidden), ["k1"])
  for (const junk of ["", "not json", "[]", "null", '{"lastSeen":"x","hidden":5}'])
    assert.equal(H.parseConfig(junk, now).lastSeen, 0, junk)
})

test("a v1 config's hidden array migrates, stamped with the load time", () => {
  const hidden = H.parseConfig('{"hidden":["a","b!"]}', now).hidden
  assert.deepEqual(plain(hidden), { a: now }, "invalid keys dropped, valid ones not expired")
})

test("a config with malformed hidden keys loads without them", () => {
  const text = JSON.stringify({ hidden: { "bad key!": now, ["x".repeat(121)]: now, ok: now } })
  assert.deepEqual(Object.keys(H.parseConfig(text, now).hidden), ["ok"])
})

test("an oversized config file is ignored, not parsed", () => {
  const text = JSON.stringify({ lastSeen: 5 }) + " ".repeat(65536)
  assert.equal(H.parseConfig(text, now).lastSeen, 0)
})

// ---- hidden keys

test("hidden keys expire after seven days, not before", () => {
  const out = H.pruneHidden({ old: now - 8 * DAY, recent: now - 6 * DAY, edge: now - H.HIDDEN_MAX_AGE }, now)
  assert.deepEqual(Object.keys(out).sort(), ["edge", "recent"])
})

test("at the hidden-key limit the oldest go and a new hide still sticks", () => {
  const hidden = {}
  for (let i = 0; i < H.HIDDEN_LIMIT; i++) hidden["old" + i] = now - 1000 - i
  const next = H.hide({ ...empty(), hidden }, "fresh", now)
  assert.equal(Object.keys(next.hidden).length, H.HIDDEN_LIMIT)
  assert.equal(next.hidden.fresh, now)
  assert.equal(next.hidden["old" + (H.HIDDEN_LIMIT - 1)], undefined, "the oldest was dropped")
  assert.equal(H.visibleRows([{ key: "fresh", ts: now - 5 }], next).length, 0)
})

// ---- enteredAt and the "since you last ..." comparisons

test("enteredAt is the later of arrival and popup close, ignoring junk", () => {
  assert.equal(H.enteredAt({ ts: 7, closed_ts: 9 }), 9)
  assert.equal(H.enteredAt({ ts: 7 }), 7)
  assert.equal(H.enteredAt({ ts: 7, closed_ts: "x" }), 7)
  assert.equal(H.enteredAt({ ts: 7, closed_ts: 1e999 }), 7, "an infinite close time is junk")
  assert.equal(H.enteredAt(null), 0)
})

test("a popup still up at close, Mark all read or Clear is not lost", () => {
  const T0 = now - 100
  const row = { key: "r", app: "A", ts: T0, closed_ts: T0 + 5 }
  assert.equal(H.newCount([row], { ...empty(), lastOpened: T0 + 3 }), 1)
  assert.equal(H.unreadCount([row], { ...empty(), lastSeen: T0 + 3 }), 1)
  assert.equal(H.visibleRows([row], { ...empty(), clearedAt: T0 + 3 }).length, 1)
  assert.equal(plain(H.countByApp([row], T0 + 3)).a, 1, "the group header counts it too")
})

test("a row that entered exactly at a cutoff is not new, unread or cleared-past", () => {
  const row = { key: "r", app: "A", ts: now - 10, closed_ts: now }
  assert.equal(H.newCount([row], H.markOpened(empty(), now)), 0)
  assert.equal(H.unreadCount([row], { ...empty(), lastSeen: now }), 0)
  assert.equal(H.visibleRows([row], { ...empty(), clearedAt: now }).length, 0)
  assert.deepEqual(plain(H.countByApp([row], now)), {})
})

test("new is a subset of unread; closing and Mark all read clear it", () => {
  const rows = sample()
  const state = { ...empty(), lastOpened: now - 20 }
  assert.equal(H.newCount(rows, state), 8)
  assert.equal(H.unreadCount(rows, state), 13)
  assert.deepEqual(plain(H.countByApp(rows, H.newSince(state))), { a: 8 })
  assert.deepEqual(plain(H.countByApp(rows, 0)), { a: 8, b: 3, c: 2 })
  const closed = H.markOpened(state, now)
  assert.equal(H.newCount(rows, closed), 0)
  assert.equal(H.unreadCount(rows, closed), 13)
  assert.equal(H.markOpened(closed, now - 1000).lastOpened, now, "never moves back")
  const read = H.markRead(state, rows, now)
  assert.equal(H.newCount(rows, read), 0)
  assert.equal(H.unreadCount(rows, read), 0)
})

test("hidden rows count as neither new nor unread", () => {
  const rows = [{ key: "a", app: "A", ts: now - 10 }, { key: "b", app: "A", ts: now - 9 }]
  const state = H.hide({ ...empty(), lastOpened: now - 100 }, "a", now)
  assert.equal(H.unreadCount(rows, state), 1)
  assert.equal(H.newCount(rows, state), 1)
})

test("Mark all read covers a row that closed after it ran, and never moves back", () => {
  const row = { key: "r", app: "A", ts: now - 10, closed_ts: now + 5 }
  assert.equal(H.unreadCount([row], H.markRead(empty(), [row], now)), 0)
  assert.equal(H.markRead({ ...empty(), lastSeen: now + 100 }, [], now).lastSeen, now + 100)
})

// ---- clear

test("Clear hides rows without a usable key and rows that closed after it ran", () => {
  const keyless = { app: "A", ts: now - 1, closed_ts: now + 5 }
  assert.equal(H.visibleRows([keyless], H.clear(empty(), [keyless], now)).length, 0)
  const badKey = { key: "bad key!", app: "A", ts: now - 10 }
  assert.equal(H.visibleRows([badKey], H.clear(empty(), [badKey], now)).length, 0)
})

test("a cleared row stays hidden by its key when a history rewrite moves it later", () => {
  const row = { key: "r", app: "A", ts: now - 10 }
  const cleared = H.clear(empty(), [row], now)
  assert.equal(H.visibleRows([{ ...row, closed_ts: now + 50 }], cleared).length, 0)
})

test("every state change keeps the other fields", () => {
  const rows = sample()
  const state = { lastSeen: 3, lastOpened: now - 100, clearedAt: 0, hidden: {} }
  for (const next of [H.hide(state, "a0", now), H.clear(state, rows, now), H.markRead(state, rows, now)])
    assert.equal(next.lastOpened, now - 100)
  assert.equal(H.markOpened(state, now).lastSeen, 3)
})

// ---- undo

test("undo reverses removals in stack order and out of order", () => {
  const rows = sample().slice(0, 4).map((row, i) => ({ ...row, app: i < 2 ? "X" : "Y" }))
  let state = empty()
  const stack = []
  const remove = (change) => { const before = state; state = change(state); stack.push({ before, after: state }) }
  const undo = () => { const step = stack.pop(); state = H.undoHide(state, step.before, step.after, now + 99) }

  remove((s) => H.hide(s, "a0", now + 1))
  remove((s) => ["a2", "a3"].reduce((next, key) => H.hide(next, key, now + 2), s))
  remove((s) => H.clear(s, rows, now + 3))
  assert.equal(keys(H.visibleRows(rows, state)), "")
  undo(); assert.equal(keys(H.visibleRows(rows, state)), "a1")
  undo(); assert.equal(keys(H.visibleRows(rows, state)), "a1 a2 a3")
  undo(); assert.equal(keys(H.visibleRows(rows, state)), "a0 a1 a2 a3")

  // Undoing an older step keeps a newer one; same-second hides stay apart.
  state = empty(); stack.length = 0
  remove((s) => H.hide(s, "a0", now)); remove((s) => H.hide(s, "a1", now))
  const older = stack[0]
  assert.equal(keys(H.visibleRows(rows, H.undoHide(state, older.before, older.after, now + 5))), "a0 a2 a3")
  undo(); assert.equal(keys(H.visibleRows(rows, state)), "a1 a2 a3")
})

test("undoing an older hide keeps a later Clear's watermark", () => {
  const rows = [{ app: "A", ts: now - 20 }, { key: "a0", app: "A", ts: now - 10 }]
  const hidden = H.hide(empty(), "a0", now)
  const cleared = H.clear(hidden, rows, now + 1)
  assert.equal(H.visibleRows(rows, H.undoHide(cleared, empty(), hidden, now + 2)).length, 0)
})

test("undo keeps what happened after the step", () => {
  const rows = sample()
  const before = empty()
  const after = H.clear(before, rows, now)
  const fresh = { key: "n", app: "N", ts: now + 5, closed_ts: now + 6 }
  let later = H.hide(after, "n", now + 6)
  later = H.markRead(later, [fresh, ...rows], now + 7)
  const undone = H.undoHide(later, before, after, now + 8)
  assert.equal(H.visibleRows([fresh, ...rows], undone).length, rows.length, "the later hide survives")
  assert.ok(undone.lastSeen >= now + 7, "the later mark-read survives")
  // A row the clear hid and the user hid again later stays hidden.
  const rehidden = H.hide(after, "b1", now + 9)
  assert.ok(!keys(H.visibleRows(rows, H.undoHide(rehidden, before, after, now + 10))).includes("b1"))
})

test("undo brings back keys the step's pruning dropped", () => {
  const many = {}
  for (let i = 0; i < H.HIDDEN_LIMIT; i++) many["old" + i] = now - 1000 - i
  const before = { ...empty(), hidden: many }
  const after = H.clear(before, sample(), now)
  assert.ok(Object.keys(after.hidden).length <= H.HIDDEN_LIMIT)
  const undone = H.undoHide(after, before, after, now + 1)
  assert.deepEqual(Object.keys(undone.hidden).sort(), Object.keys(many).sort())
  assert.doesNotThrow(() => { H.undoHide(null, null, null, now); H.undoHide({}, {}, {}, now) })
})

test("a key re-hidden after the step that pruned it keeps its newer time through undo", () => {
  // k is the oldest of HIDDEN_LIMIT keys, so the step's hide of x pushes it out.
  const many = {}
  for (let i = 0; i < H.HIDDEN_LIMIT - 1; i++) many["old" + i] = now - 1000 - i
  const before = { ...empty(), hidden: { ...many, k: now - 5000 } }
  const after = H.hide(before, "x", now)
  assert.equal(after.hidden.k, undefined, "the step's pruning dropped k")
  const later = H.hide(after, "k", now + 1)
  const undone = H.undoHide(later, before, after, now + 2)
  assert.equal(undone.hidden.k, now + 1, "an older stamp would expire it days early")
  assert.equal(undone.hidden.x, undefined)
})

// ---- grouping, display and search

test("groupByApp keeps groups where their newest row stood, with positions", () => {
  const rows = [{ key: "1", app: "A" }, { key: "2", app: "b" }, { key: "3", app: "a " }, { key: "4", app: "__proto__" }]
  const grouped = plain(H.groupByApp(rows))
  assert.deepEqual(grouped.map((g) => g.row.key), ["1", "3", "2", "4"])
  assert.deepEqual(grouped.map((g) => g.groupIndex), [0, 1, 0, 0])
  assert.deepEqual(grouped.map((g) => g.groupSize), [2, 2, 1, 1])
  assert.deepEqual(grouped.map((g) => g.groupStart), [true, false, true, true])
})

test("a row with no app groups under its source", () => {
  const grouped = plain(H.groupByApp([{ key: "1", source: "Firefox" }, { key: "2", app: "firefox" }]))
  assert.deepEqual(grouped.map((g) => g.groupSize), [2, 2])
})

test("shownItems: collapse, Expand all preview, unread beyond it, and full groups", () => {
  const rows = sample()
  const grouped = H.groupByApp(rows)
  const show = (collapsed, expandAll, full, unread) =>
    keys(H.shownItems(grouped, collapsed, expandAll, full, unread || {}, 5, 100).map((item) => item.row))
  assert.equal(show([], false, []), keys(rows))
  assert.equal(show(["a", "b", "c"], false, []), "a0 b0 c0")
  assert.equal(show([], true, []), "a0 a1 a2 a3 a4 b0 b1 b2 c0 c1")
  assert.equal(show([], true, [], { a: 7 }), "a0 a1 a2 a3 a4 a5 a6 b0 b1 b2 c0 c1")
  assert.equal(show([], true, ["a"]), keys(rows))
  assert.equal(show(["a"], true, ["a"]), "a0 b0 b1 b2 c0 c1", "collapsed wins")
  assert.equal(H.shownItems(grouped, [], false, [], {}, 5, 4).length, 4, "limit")
})

test("search matches every word across app, source, title and body", () => {
  const rows = [{ app: "Mail", summary: "Invoice due", body: "Pay by Friday" }, { app: "Chat", summary: "Hi" }]
  assert.equal(H.filterRows(rows, "mail friday").length, 1)
  assert.equal(H.filterRows(rows, "mail hi").length, 0, "every word, not any")
  assert.equal(H.filterRows(rows, "  ").length, 2)
  assert.equal(H.filterRows(rows, "nothing").length, 0)
  assert.equal(H.filterRows([{ source: "Firefox", summary: "Download done" }], "firefox done").length, 1)
})

test("removing a selected row keeps the selection in its group", () => {
  // Chat sorts first only because of its newest row; removing that row moves
  // Chat below tidal-hifi, so the next slot would be another app's row.
  const rows = [
    { key: "c2", app: "Chat" }, { key: "c1", app: "Chat" },
    { key: "t1", app: "tidal-hifi" }, { key: "m1", app: "Mail" },
  ]
  const items = H.groupByApp(rows)
  const at = (index) => (index < 0 ? null : items[index].row.key)
  assert.equal(at(H.neighbourInGroup(items, 0)), "c1", "next row of the group")
  assert.equal(at(H.neighbourInGroup(items, 1)), "c2", "last row of a group: the previous one")
  assert.equal(H.neighbourInGroup(items, 2), -1, "a group's only row: no neighbour")
  assert.equal(H.neighbourInGroup(items, 3), -1, "the last item, alone in its group")
  assert.equal(H.neighbourInGroup(items, 9), -1)
  assert.equal(H.neighbourInGroup(items, -1), -1)
})
