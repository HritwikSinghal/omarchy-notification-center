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
    return { version: CONFIG_VERSION, lastSeen: 0, clearedAt: 0, hidden: {} }

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
    clearedAt: finite(value.clearedAt, 0),
    hidden: pruneHidden(hidden, at)
  }
}

function serialiseConfig(state) {
  var clean = parseConfig(JSON.stringify(state || {}), nowSeconds())
  return JSON.stringify({
    version: CONFIG_VERSION,
    lastSeen: clean.lastSeen,
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
    if (tsOf(row) <= current.clearedAt) continue
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
    if (tsOf(visible[i]) > current.lastSeen) unread++
  return unread
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
    newest = Math.max(newest, tsOf(visible[i]))
  }
  // The key set covers malformed/future entries exactly; the watermark covers
  // all older native rows when history.json is atomically rewritten.
  next.clearedAt = Math.max(next.clearedAt, at, newest)
  next.hidden = pruneHidden(next.hidden, at)
  return next
}

function markRead(state, rows, now) {
  var at = finite(now, nowSeconds())
  var next = stateCopy(state, at)
  var visible = visibleRows(rows, next)
  var newest = 0
  for (var i = 0; i < visible.length; i++) newest = Math.max(newest, tsOf(visible[i]))
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

// Rows regrouped by app for display, as [{ row, groupStart, groupSize }]. The
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
      out.push({ row: members[j], groupStart: j === 0, groupSize: members.length })
  })
  return out
}
