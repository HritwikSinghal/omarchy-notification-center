.pragma library

// Local, read-only filtering for Omarchy's native notification history. Native
// keys are generated once per notification and retained across history rewrites,
// so they are the only identity this plugin persists.
var CONFIG_VERSION = 2
var HIDDEN_LIMIT = 256
var HIDDEN_MAX_AGE = 7 * 24 * 60 * 60
var KEY = /^[A-Za-z0-9_-]{1,120}$/

function nowSeconds() { return Date.now() / 1000 }

function finite(value, fallback) {
  var number = Number(value)
  return isFinite(number) && number >= 0 ? number : fallback
}

function keyOf(row) {
  var key = String((row && row.key) || "")
  return KEY.test(key) ? key : ""
}

function tsOf(row) {
  var timestamp = Number((row && row.ts) || 0)
  return isFinite(timestamp) && timestamp >= 0 ? timestamp : 0
}

// When a row entered Omarchy's history. The daemon writes a row when its popup
// closes (closed_ts) but stamps it with its arrival (ts), so a notification
// whose popup was still up when the panel closed, or when Mark all read or a
// clear ran, would land already "seen". Every "since you last ..." comparison
// uses this instead of ts.
function enteredAt(row) {
  var closed = Number((row && row.closed_ts) || 0)
  return Math.max(tsOf(row), isFinite(closed) && closed >= 0 ? closed : 0)
}

function pruneHidden(hidden, now) {
  var at = finite(now, nowSeconds())
  var cutoff = Math.max(0, at - HIDDEN_MAX_AGE)
  var kept = []
  if (!hidden || typeof hidden !== "object" || Array.isArray(hidden)) return {}
  for (var key in hidden) {
    if (!KEY.test(key)) continue
    var hiddenAt = finite(hidden[key], 0)
    if (hiddenAt < cutoff) continue
    kept.push({ key: key, at: hiddenAt })
  }
  kept.sort(function(a, b) {
    if (b.at !== a.at) return b.at - a.at
    return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
  })
  var out = {}
  for (var i = 0; i < kept.length && i < HIDDEN_LIMIT; i++) out[kept[i].key] = kept[i].at
  return out
}

function parseConfig(text, now) {
  var at = finite(now, nowSeconds())
  var raw = String(text || "")
  var value = null
  if (raw.length <= 65536 && raw.trim()) {
    try { value = JSON.parse(raw) } catch (error) { value = null }
  }
  if (!value || typeof value !== "object" || Array.isArray(value))
    return { version: CONFIG_VERSION, lastSeen: 0, lastOpened: 0, clearedAt: 0, hidden: {} }

  var hidden = {}
  // v1 stored an array. Its keys remain valid; stamp migration with the load
  // time so pruning cannot turn it into an unbounded legacy collection.
  if (Array.isArray(value.hidden)) {
    for (var i = 0; i < value.hidden.length; i++) {
      var legacyKey = String(value.hidden[i] || "")
      if (KEY.test(legacyKey)) hidden[legacyKey] = at
    }
  } else if (value.hidden && typeof value.hidden === "object") {
    hidden = value.hidden
  }
  return {
    version: CONFIG_VERSION,
    lastSeen: finite(value.lastSeen, 0),
    lastOpened: finite(value.lastOpened, 0),
    clearedAt: finite(value.clearedAt, 0),
    hidden: pruneHidden(hidden, at)
  }
}

function serialiseConfig(state) {
  var clean = parseConfig(JSON.stringify(state || {}), nowSeconds())
  return JSON.stringify({
    version: CONFIG_VERSION,
    lastSeen: clean.lastSeen,
    lastOpened: clean.lastOpened,
    clearedAt: clean.clearedAt,
    hidden: clean.hidden
  }, null, 2) + "\n"
}

function stateCopy(state, now) {
  return parseConfig(JSON.stringify(state || {}), now)
}

function visibleRows(rows, state) {
  var current = stateCopy(state, nowSeconds())
  var source = Array.isArray(rows) ? rows : []
  var out = []
  for (var i = 0; i < source.length; i++) {
    var row = source[i]
    var key = keyOf(row)
    if (enteredAt(row) <= current.clearedAt) continue
    if (key && current.hidden[key] !== undefined) continue
    out.push(row)
  }
  return out
}

function unreadCount(rows, state) {
  var current = stateCopy(state, nowSeconds())
  var visible = visibleRows(rows, current)
  var unread = 0
  for (var i = 0; i < visible.length; i++)
    if (enteredAt(visible[i]) > current.lastSeen) unread++
  return unread
}

// A row is new when it entered history (enteredAt) after the panel last
// closed. Mark all read covers new rows too, so the cutoff is whichever of the
// two is later.
function newSince(state) {
  var current = stateCopy(state, nowSeconds())
  return Math.max(current.lastOpened, current.lastSeen)
}

function newCount(rows, state) {
  var cutoff = newSince(state)
  var visible = visibleRows(rows, state)
  var count = 0
  for (var i = 0; i < visible.length; i++)
    if (enteredAt(visible[i]) > cutoff) count++
  return count
}

// Rows per app (appKey) that arrived after `cutoff`: with newSince, the new
// count on a group's header; with lastSeen, its unread count.
function countByApp(rows, cutoff) {
  var source = Array.isArray(rows) ? rows : []
  var out = {}
  for (var i = 0; i < source.length; i++) {
    if (enteredAt(source[i]) <= cutoff) continue
    var key = appKey(source[i])
    out[key] = (out[key] || 0) + 1
  }
  return out
}

// Stamped as the panel closes: what was on screen then is no longer new.
function markOpened(state, now) {
  var at = finite(now, nowSeconds())
  var next = stateCopy(state, at)
  next.lastOpened = Math.max(next.lastOpened, at)
  return next
}

function hide(state, key, now) {
  var at = finite(now, nowSeconds())
  var next = stateCopy(state, at)
  var stableKey = String(key || "")
  if (KEY.test(stableKey)) next.hidden[stableKey] = at
  next.hidden = pruneHidden(next.hidden, at)
  return next
}

function clear(state, rows, now) {
  var at = finite(now, nowSeconds())
  var next = stateCopy(state, at)
  var visible = visibleRows(rows, next)
  var newest = 0
  for (var i = 0; i < visible.length; i++) {
    var key = keyOf(visible[i])
    if (key) next.hidden[key] = at
    newest = Math.max(newest, enteredAt(visible[i]))
  }
  // The key set covers malformed/future entries exactly; the watermark covers
  // all older native rows when history.json is atomically rewritten.
  next.clearedAt = Math.max(next.clearedAt, at, newest)
  next.hidden = pruneHidden(next.hidden, at)
  return next
}

// Reverses one removal (hide, a group's hides, or clear), given the state just
// before it and just after it, on top of whatever happened since: only what
// that step changed is put back, so a row hidden or a mark-read made
// afterwards survives the undo. Keys it added are dropped unless re-hidden
// since; keys its pruning dropped return; a clear's watermark is restored.
function undoHide(state, before, after, now) {
  var at = finite(now, nowSeconds())
  var next = stateCopy(state, at)
  var was = stateCopy(before, at)
  var cleared = stateCopy(after, at)
  for (var key in cleared.hidden)
    if (was.hidden[key] === undefined && next.hidden[key] === cleared.hidden[key])
      delete next.hidden[key]
  for (var oldKey in was.hidden)
    if (cleared.hidden[oldKey] === undefined && next.hidden[oldKey] === undefined)
      next.hidden[oldKey] = was.hidden[oldKey]
  if (next.clearedAt === cleared.clearedAt) next.clearedAt = was.clearedAt
  next.hidden = pruneHidden(next.hidden, at)
  return next
}

function markRead(state, rows, now) {
  var at = finite(now, nowSeconds())
  var next = stateCopy(state, at)
  var visible = visibleRows(rows, next)
  var newest = 0
  for (var i = 0; i < visible.length; i++) newest = Math.max(newest, enteredAt(visible[i]))
  next.lastSeen = Math.max(next.lastSeen, at, newest)
  return next
}

// Whether a row matches a search query: every whitespace-separated word must
// appear, case-insensitively, in its app, source, title or body. An empty
// query matches every row.
function matchesQuery(row, query) {
  var words = String(query || "").toLowerCase().split(/\s+/).filter(function(word) { return word !== "" })
  if (words.length === 0) return true
  var fields = [row && row.app, row && row.source, row && row.summary, row && row.body]
  var haystack = fields.map(function(value) { return String(value || "") }).join("\n").toLowerCase()
  for (var i = 0; i < words.length; i++)
    if (haystack.indexOf(words[i]) < 0) return false
  return true
}

function filterRows(rows, query) {
  var source = Array.isArray(rows) ? rows : []
  return source.filter(function(row) { return matchesQuery(row, query) })
}

// The app a row is grouped under: its app name, else its source, compared
// case-insensitively. "" when it has neither; those form one group of their own.
function appKey(row) {
  return String((row && (row.app || row.source)) || "").trim().toLowerCase()
}

// Rows regrouped by app for display, as [{ row, groupStart, groupIndex,
// groupSize }], groupIndex being the row's place in its group. The
// input is newest first, so a group sits where its newest row stood and keeps
// its rows newest first. A Map, not an object, so an app named "__proto__"
// cannot reach the prototype.
function groupByApp(rows) {
  var source = Array.isArray(rows) ? rows : []
  var groups = new Map()
  for (var i = 0; i < source.length; i++) {
    var key = appKey(source[i])
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(source[i])
  }
  var out = []
  groups.forEach(function(members) {
    for (var j = 0; j < members.length; j++)
      out.push({ row: members[j], groupStart: j === 0, groupIndex: j, groupSize: members.length })
  })
  return out
}

// The items HistoryList draws, from groupByApp's output: every group's first
// row (its header sits on it); nothing more of a collapsed group; under Expand
// all, the newest `preview` rows or all its unread ones if more, unless the
// group was unfolded by hand (`full`); otherwise every row. At most `limit`.
function shownItems(grouped, collapsed, expandAll, full, unreadByApp, preview, limit) {
  var source = Array.isArray(grouped) ? grouped : []
  var out = []
  for (var i = 0; i < source.length && out.length < limit; i++) {
    var item = source[i]
    var key = appKey(item.row)
    if (item.groupStart) out.push(item)
    else if (collapsed.indexOf(key) >= 0) continue
    else if (!expandAll || full.indexOf(key) >= 0) out.push(item)
    else if (item.groupIndex < Math.max(preview, (unreadByApp && unreadByApp[key]) || 0)) out.push(item)
  }
  return out
}
