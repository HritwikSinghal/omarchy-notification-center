.pragma library

// Cover art for media notifications. Omarchy's daemon never stores a
// notification's image (Store.js: "codes, links and images never persist"),
// so the history only says "tidal-hifi". ArtRecorder.qml notes each track
// MPRIS players announce -- app, title, artist, art URL, when -- and rows find
// their cover here.
//
// A row only takes a cover recorded from its own app, so a screenshot tool's
// "Done" never picks up a song called "Done". Among those, an exact
// title+artist match wins, the play nearest the row's time when there are
// several; else the title alone when the track started within WINDOW of the
// notification, which covers tidal-hifi sending the new title with the
// previous track's artist.

var LIMIT = 300
var MAX_AGE = 7 * 24 * 60 * 60
var WINDOW = 120
var MAX_URL = 2048

function norm(value) {
  return String(value || "").trim().toLowerCase()
}

// Apps compare by letters and digits only: tidal-hifi's notifications say
// "tidal-hifi" while its MPRIS identity is "Tidal Hi-Fi".
function appKey(value) {
  return norm(value).replace(/[^a-z0-9]/g, "")
}

// Only URLs an Image can load without surprises: remote https, or a local
// file. data: URIs (mpv's inline covers) run to hundreds of KB, so they are
// not kept.
function safeUrl(value) {
  var url = String(value || "")
  if (url.length > MAX_URL || /[\x00-\x20\x7f]/.test(url)) return ""
  return /^https:\/\/[^/]/i.test(url) || /^file:\/\/\//i.test(url) ? url : ""
}

// A remote cover outlives a local one: Chromium-based players (tidal-hifi's
// second MPRIS endpoint) hand out file:///tmp/.org.chromium.* copies that are
// deleted soon after, while the app's own endpoint gives the same cover as
// https.
function lasting(entry) {
  return /^https:/i.test(String(entry.art))
}

function validEntry(entry) {
  return !!entry && typeof entry === "object" && norm(entry.title) !== ""
    && safeUrl(entry.art) !== "" && isFinite(Number(entry.ts))
}

function sameTrack(a, b) {
  return appKey(a.app) === appKey(b.app) && norm(a.title) === norm(b.title)
    && norm(a.artist) === norm(b.artist)
}

function clean(entry, ts) {
  return {
    app: String(entry.app || "").trim(),
    title: String(entry.title || "").trim(),
    artist: String(entry.artist || "").trim(),
    art: safeUrl(entry.art),
    ts: Number(ts)
  }
}

// One cache from any number of entry lists: one entry per track (app, title,
// artist), keeping its latest time and its lasting cover when it has one;
// newest first, past MAX_AGE (from `now`) or LIMIT dropped.
function merge(lists, now) {
  var at = Number(now)
  var tracks = []
  for (var l = 0; l < lists.length; l++) {
    var list = Array.isArray(lists[l]) ? lists[l] : []
    for (var i = 0; i < list.length; i++) {
      var entry = clean(list[i] || {}, (list[i] || {}).ts)
      if (!validEntry(entry) || at - entry.ts > MAX_AGE) continue
      var found = -1
      for (var t = 0; t < tracks.length; t++) {
        if (sameTrack(tracks[t], entry)) {
          found = t
          break
        }
      }
      if (found < 0) {
        tracks.push(entry)
        continue
      }
      var kept = tracks[found]
      // A lasting cover beats a temp copy; between two of a kind, the newer.
      var art
      if (lasting(entry) !== lasting(kept)) art = lasting(entry) ? entry.art : kept.art
      else art = entry.ts >= kept.ts ? entry.art : kept.art
      tracks[found] = { app: kept.app || entry.app, title: kept.title, artist: kept.artist,
                        art: art, ts: Math.max(kept.ts, entry.ts) }
    }
  }
  tracks.sort(function(a, b) { return b.ts - a.ts })
  return tracks.slice(0, LIMIT)
}

// The cache with `track` ({ app, title, artist, art }) recorded at `now`
// (seconds). An invalid track leaves the cache as it was (the same array).
function record(entries, track, now) {
  var entry = clean(track || {}, now)
  if (!validEntry(entry)) return Array.isArray(entries) ? entries : []
  return merge([[entry], entries], now)
}

// The cover for a history row, or "". Its title is `summary`, its artists
// `body` (what tidal-hifi and most players send), its app `app`. Entries
// recorded without an app (older caches) match any app.
function lookup(entries, row) {
  var title = norm(row && row.summary)
  if (title === "" || !Array.isArray(entries)) return ""
  var app = appKey(row.app)
  var artist = norm(row.body)
  var ts = Number((row && row.ts) || 0)
  var exact = null, exactGap = Infinity, near = null, nearGap = Infinity
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!validEntry(entry) || norm(entry.title) !== title) continue
    if (appKey(entry.app) !== "" && appKey(entry.app) !== app) continue
    var gap = Math.abs(Number(entry.ts) - ts)
    if (artist !== "" && norm(entry.artist) === artist && gap < exactGap) {
      exact = entry
      exactGap = gap
    }
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
  for (var i = 0; i < value.length && out.length < LIMIT; i++) {
    var entry = clean(value[i] || {}, (value[i] || {}).ts)
    if (validEntry(entry)) out.push(entry)
  }
  return out
}

function serialise(entries) {
  return JSON.stringify(Array.isArray(entries) ? entries : []) + "\n"
}
