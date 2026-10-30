.pragma library

// Cover art for media notifications. Omarchy's daemon never stores a
// notification's image (Store.js: "codes, links and images never persist"),
// so the history only says "tidal-hifi". ArtRecorder.qml notes each track
// MPRIS players announce -- title, artist, art URL, when -- and rows find
// their cover here by matching their title and artist.
//
// Matching copes with tidal-hifi's notifications, which can carry the new
// title with the previous track's artist: an exact title+artist match wins,
// else the title alone when the track started within WINDOW of the
// notification.

var LIMIT = 300
var MAX_AGE = 7 * 24 * 60 * 60
var WINDOW = 120
var MAX_URL = 2048

function norm(value) {
  return String(value || "").trim().toLowerCase()
}

// Only URLs an Image can load without surprises: remote https, or a local
// file. data: URIs (mpv's inline covers) run to hundreds of KB, so they are
// not kept.
function safeUrl(value) {
  var url = String(value || "")
  if (url.length > MAX_URL || /[\x00-\x20\x7f]/.test(url)) return ""
  return /^https:\/\/[^/]/i.test(url) || /^file:\/\/\//i.test(url) ? url : ""
}

function validEntry(entry) {
  return !!entry && typeof entry === "object" && norm(entry.title) !== ""
    && safeUrl(entry.art) !== "" && isFinite(Number(entry.ts))
}

// The cache with `track` ({ title, artist, art }) recorded at `now`
// (seconds): a repeat of the same title, artist and art refreshes its time
// instead of adding a row. Oldest entries go past MAX_AGE or LIMIT.
function record(entries, track, now) {
  var at = Number(now)
  var entry = {
    title: String((track && track.title) || "").trim(),
    artist: String((track && track.artist) || "").trim(),
    art: safeUrl(track && track.art),
    ts: at
  }
  var source = Array.isArray(entries) ? entries : []
  if (!validEntry(entry)) return source
  var out = [entry]
  for (var i = 0; i < source.length && out.length < LIMIT; i++) {
    var old = source[i]
    if (!validEntry(old) || at - Number(old.ts) > MAX_AGE) continue
    if (norm(old.title) === norm(entry.title) && norm(old.artist) === norm(entry.artist)
        && old.art === entry.art) continue
    out.push(old)
  }
  return out
}

// The cover for a history row, or "". Its title is `summary`, its artists
// `body` (what tidal-hifi and most players send).
function lookup(entries, row) {
  var title = norm(row && row.summary)
  if (title === "" || !Array.isArray(entries)) return ""
  var artist = norm(row.body)
  var ts = Number((row && row.ts) || 0)
  var exact = null, near = null, nearGap = Infinity
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!validEntry(entry) || norm(entry.title) !== title) continue
    // Entries are newest first, so the first exact match is the latest play.
    if (exact === null && artist !== "" && norm(entry.artist) === artist) exact = entry
    var gap = Math.abs(Number(entry.ts) - ts)
    if (gap <= WINDOW && gap < nearGap) {
      near = entry
      nearGap = gap
    }
  }
  return exact ? exact.art : (near ? near.art : "")
}

function parse(text) {
  var raw = String(text || "")
  if (!raw.trim() || raw.length > LIMIT * (MAX_URL + 1024)) return []
  var value
  try { value = JSON.parse(raw) } catch (error) { return [] }
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length && out.length < LIMIT; i++)
    if (validEntry(value[i]))
      out.push({ title: String(value[i].title), artist: String(value[i].artist || ""),
                 art: String(value[i].art), ts: Number(value[i].ts) })
  return out
}

function serialise(entries) {
  return JSON.stringify(Array.isArray(entries) ? entries : []) + "\n"
}
