.pragma library

// Debug logging for the panel, shared by every file that imports it (a
// .pragma library has one instance). Lines go to the shell's log
// ($XDG_RUNTIME_DIR/quickshell/by-id/*/log.log, as "qml: [nc:<area>] ...").
//
// Off by default. Turn it on with
//   omarchy-shell notification-center debug on
// (persisted in ~/.config/omarchy/gabodev.notification-center/debug), and dump
// the panel's live state with
//   omarchy-shell notification-center state
//
// Areas: panel (open/close, actions), history (loads), list (model sync,
// selection), search, capture (image helper).

var enabled = false

function text(parts) {
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (typeof part === "string") out.push(part)
    else {
      try { out.push(JSON.stringify(part)) } catch (error) { out.push(String(part)) }
    }
  }
  return out.join(" ")
}

// Detail, only while debugging is on.
function log(area) {
  if (!enabled) return
  console.log("[nc:" + area + "] " + text(Array.prototype.slice.call(arguments, 1)))
}

// Problems, always logged.
function warn(area) {
  console.warn("[nc:" + area + "] " + text(Array.prototype.slice.call(arguments, 1)))
}
