.pragma library

// Keyboard shortcuts for the footer actions. SearchField matches keys against
// this table and PanelFooter prints the labels under its buttons, so a hint
// can never drift from the key that works. Letters avoid the ones Qt's text
// input already binds on Linux (Ctrl+A/E/K/U and the clipboard keys).
var actions = {
  markRead: { key: "M", label: "Ctrl+M" },
  closeAll: { key: "D", label: "Ctrl+D" },  // "dismiss"
  clear: { key: "L", label: "Ctrl+L" },
  // Only while a clear can be undone; otherwise Ctrl+Z undoes typing.
  undo: { key: "Z", label: "Ctrl+Z" }
}

// Close is Esc, which SearchField already steps back through.
var closeLabel = "Esc"

// The action a key press with Ctrl alone selects, or "" for any other press.
// Qt key codes for A-Z equal the uppercase character codes.
function actionFor(key, ctrl, otherModifiers) {
  if (!ctrl || otherModifiers)
    return ""
  for (var name in actions)
    if (actions[name].key.charCodeAt(0) === key)
      return name
  return ""
}
