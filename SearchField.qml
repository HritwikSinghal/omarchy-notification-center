import QtQuick
import qs.Commons
import qs.Commons as Commons

import "Fonts.js" as Fonts

// The search line: the panel filters rows by app, title and body as you type
// (History.matchesQuery). A plain TextInput rather than the shell's
// FilterInput, which is append-only because the menu owns the arrow keys; here
// the query is ordinary editable text. Esc clears a query first, then closes.
Rectangle {
  id: root

  required property var tr
  readonly property string text: input.text

  signal dismissRequested()

  function focusInput() { input.forceActiveFocus() }
  function clear() { input.text = "" }

  width: parent ? parent.width : 0
  height: Style.space(36)
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
    font.pixelSize: Style.font.body
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
    font.pixelSize: Style.font.subtitle
    clip: true
    selectByMouse: true

    Keys.onEscapePressed: function(event) {
      if (input.text !== "") input.text = ""
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
