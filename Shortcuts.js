.pragma library

// Keyboard shortcuts for the footer actions. SearchField matches keys against
// this table and PanelFooter prints the labels under its buttons, so a hint
// can never drift from the key that works. Letters avoid the ones Qt's text
// input already binds on Linux (Ctrl+A/K/U and the clipboard keys); Ctrl+E is
// taken over on purpose.
var actions = {
  markRead: { key: "M", label: "Ctrl+M" },
  closeAll: { key: "D", label: "Ctrl+D" },  // "dismiss"
  clear: { key: "L", label: "Ctrl+L" },
  // Ctrl+E is the input's end-of-line on Linux; End still does that.
  expandAll: { key: "E", label: "Ctrl+E" },
  collapseAll: { key: "E", shift: true, label: "Ctrl+Shift+E" },
  // Only while a removal can be undone; otherwise Ctrl+Z undoes typing.
  undo: { key: "Z", label: "Ctrl+Z" }
}

// Close is Esc, which SearchField already steps back through.
var closeLabel = "Esc"

// The action a press of Ctrl (plus Shift where the table says so) selects, or
// "" for any other press. Qt key codes for A-Z equal the uppercase character
// codes, with or without Shift.
function actionFor(key, ctrl, shift, otherModifiers) {
  if (!ctrl || otherModifiers)
    return ""
  for (var name in actions)
    if (actions[name].key.charCodeAt(0) === key && !!actions[name].shift === shift)
      return name
  return ""
}
