import QtQuick
import qs.Commons
import qs.Commons as Commons

import "Fonts.js" as Fonts
import "Shortcuts.js" as Shortcuts

// The search line: the panel filters rows by app, title and body as you type
// (History.matchesQuery). A plain TextInput rather than the shell's
// FilterInput, which is append-only because the menu owns the arrow keys; here
// the query is ordinary editable text. It also carries the list's keyboard
// navigation (arrows by row, Tab by group, Enter, Delete) and the footer
// actions' Ctrl shortcuts (Shortcuts.js); Esc steps back selection, query,
// panel.
Rectangle {
  id: root

  required property var tr
  readonly property string text: input.text
  // Whether the list has a keyboard selection. Enter and Delete act on it
  // only then; with none they edit the query as usual.
  property bool hasSelection: false

  signal dismissRequested()
  // Keyboard navigation of the list, which never takes focus itself: the
  // search line keeps it so typing always searches.
  signal navigateRequested(int delta)
  signal groupNavigateRequested(int delta)
  signal activateRequested()
  signal deleteRequested(bool wholeGroup)
  signal collapseRequested(bool collapse)
  signal clearSelectionRequested()
  // A footer action by its Shortcuts.actions name: markRead, closeAll, clear.
  signal shortcutPressed(string action)

  function focusInput() { input.forceActiveFocus() }
  function clear() { input.text = "" }

  width: parent ? parent.width : 0
  height: Style.space(40)
  radius: Style.space(6)
  color: Util.alpha(Commons.Color.popups.text, 0.06)
  border.width: 1
  border.color: input.activeFocus
    ? Util.alpha(Commons.Color.accent, 0.6)
    : Util.alpha(Commons.Color.popups.text, 0.1)

  // Below the input, so a click anywhere on the field focuses it without
  // stealing the input's own clicks.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.IBeamCursor
    onClicked: input.forceActiveFocus()
  }

  Text {
    id: glyph
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    text: "\uf002"
    color: Util.alpha(Commons.Color.popups.text, 0.5)
    font.family: Style.font.family
    font.pixelSize: Fonts.px(Style.font.body, Fonts.meta)
    textFormat: Text.PlainText
  }

  TextInput {
    id: input
    anchors.left: glyph.right
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    color: Commons.Color.popups.text
    selectionColor: Util.alpha(Commons.Color.accent, 0.4)
    selectedTextColor: Commons.Color.popups.text
    font.family: Fonts.text
    font.pixelSize: Fonts.px(Style.font.body, Fonts.body)
    clip: true
    selectByMouse: true

    // Letters have no specific Keys handler, so they arrive here, and Keys
    // runs before the input's own editing; anything else falls through.
    Keys.onPressed: function(event) {
      var others = event.modifiers & (Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
      var action = Shortcuts.actionFor(event.key, (event.modifiers & Qt.ControlModifier) !== 0, others !== 0)
      if (action === "")
        return
      root.shortcutPressed(action)
      event.accepted = true
    }

    Keys.onUpPressed: function(event) { root.navigateRequested(-1); event.accepted = true }
    Keys.onDownPressed: function(event) { root.navigateRequested(1); event.accepted = true }
    // Tab and Shift+Tab jump between app groups; the arrows go row by row.
    Keys.onTabPressed: function(event) { root.groupNavigateRequested(1); event.accepted = true }
    Keys.onBacktabPressed: function(event) { root.groupNavigateRequested(-1); event.accepted = true }

    Keys.onReturnPressed: function(event) {
      if (root.hasSelection) root.activateRequested()
      event.accepted = true
    }
    Keys.onEnterPressed: function(event) {
      if (root.hasSelection) root.activateRequested()
      event.accepted = true
    }

    // Delete dismisses the selected row, Shift+Delete its whole group. With
    // no selection it is left to the input, which deletes forward.
    Keys.onDeletePressed: function(event) {
      if (!root.hasSelection) {
        event.accepted = false
        return
      }
      root.deleteRequested((event.modifiers & Qt.ShiftModifier) !== 0)
      event.accepted = true
    }

    // Left/Right fold the selected row's group, but only with an empty query:
    // with text they move the caret.
    Keys.onLeftPressed: function(event) {
      if (!root.hasSelection || input.text !== "") {
        event.accepted = false
        return
      }
      root.collapseRequested(true)
      event.accepted = true
    }
    Keys.onRightPressed: function(event) {
      if (!root.hasSelection || input.text !== "") {
        event.accepted = false
        return
      }
      root.collapseRequested(false)
      event.accepted = true
    }

    // Esc steps back one level: selection, then query, then the panel.
    Keys.onEscapePressed: function(event) {
      if (root.hasSelection) root.clearSelectionRequested()
      else if (input.text !== "") input.text = ""
      else root.dismissRequested()
      event.accepted = true
    }
  }

  Text {
    anchors.fill: input
    verticalAlignment: Text.AlignVCenter
    visible: input.text === ""
    text: root.tr.t("panel.search")
    color: Util.alpha(Commons.Color.popups.text, 0.4)
    font: input.font
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }
}
