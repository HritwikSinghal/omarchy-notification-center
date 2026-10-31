.pragma library

// Images notifications carried, kept by capture/notify-capture.py (Omarchy's
// history drops them). Each entry is { id, app, summary, ts, image }: `id` is
// the id the daemon gave the notification, which history rows keep as
// `originalId`. Ids restart from 1 whenever the shell restarts, so a row
// takes an image only when the app matches too and the two times are within
// WINDOW seconds; the nearest such entry wins.

var LIMIT = 300
var WINDOW = 60

function appKey(value) {
  return String(value || "").trim().toLowerCase().replace(/[^a-z0-9]/g, "")
}

// Only files in the helper's own cache directory are loaded.
function safeImage(value) {
  var url = String(value || "")
  return /^file:\/\/\/[^\s]*\/gabodev\.notification-center\/images\/[0-9a-f]{40}\.(png|jpg|gif|bmp|webp)$/.test(url) ? url : ""
}

function valid(entry) {
  return !!entry && typeof entry === "object" && isFinite(Number(entry.id)) && Number(entry.id) > 0
    && isFinite(Number(entry.ts)) && safeImage(entry.image) !== ""
}

function parse(text) {
  var value
  try { value = JSON.parse(String(text || "")) } catch (error) { return [] }
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length && out.length < LIMIT; i++)
    if (valid(value[i])) out.push(value[i])
  return out
}

// The list with one more record in front, bounded.
function add(entries, record) {
  if (!valid(record)) return entries
  return [record].concat(Array.isArray(entries) ? entries : []).slice(0, LIMIT)
}

function lookup(entries, row) {
  if (!row || !Array.isArray(entries)) return ""
  var id = Number(row.originalId || 0)
  if (!(id > 0)) return ""
  var app = appKey(row.app)
  var ts = Number(row.ts || 0)
  var best = "", bestGap = Infinity
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (Number(entry.id) !== id || appKey(entry.app) !== app) continue
    var gap = Math.abs(Number(entry.ts) - ts)
    if (gap <= WINDOW && gap < bestGap) {
      best = entry.image
      bestGap = gap
    }
  }
  return safeImage(best)
}
