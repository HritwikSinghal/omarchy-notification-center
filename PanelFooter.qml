import QtQuick
import qs.Commons
import qs.Commons as Commons

import "Fonts.js" as Fonts
import "Shortcuts.js" as Shortcuts
import qs.Ui

// The bottom of the panel: temporary feedback, the rule before the actions, the
// three list actions on the left and Close pinned to the right edge, each with
// its keyboard shortcut written under it. Every action is reported upwards; the
// panel decides what it does.
Column {
  id: root

  required property var tr
  property string feedback: ""
  property bool showRule: false

  signal markReadRequested()
  signal closeAllRequested()
  signal clearRequested()
  signal dismissRequested()

  width: parent ? parent.width : 0
  spacing: Style.spacing.panelGap

  // A footer button with its shortcut under it, so the keys are found
  // without a help screen.
  component ActionButton: Column {
    id: action

    property alias text: button.text
    property string shortcut: ""
    property color foreground: Commons.Color.popups.text

    signal clicked()

    spacing: Style.space(2)

    Button {
      id: button
      anchors.horizontalCenter: parent.horizontalCenter
      onClicked: action.clicked()
      foreground: action.foreground
      background: Commons.Color.popups.background
      accent: Commons.Color.accent
      fontFamily: Fonts.text
      fontSize: Fonts.px(Style.font.body, Fonts.meta)
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: action.shortcut
      color: Util.alpha(Commons.Color.popups.text, 0.4)
      font.family: Fonts.text
      font.pixelSize: Fonts.px(Style.font.body, Fonts.hint)
      textFormat: Text.PlainText
    }
  }

  Text {
    width: parent.width
    visible: root.feedback !== ""
    text: root.feedback
    color: Util.alpha(Commons.Color.popups.text, 0.65)
    font.family: Fonts.text
    font.pixelSize: Fonts.px(Style.font.body, Fonts.meta)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }

  // Hairline before the actions
  Rectangle {
    width: parent.width
    height: 1
    color: Util.alpha(Commons.Color.popups.text, 0.08)
    visible: root.showRule
  }

  Item {
    width: parent.width
    height: Math.max(actions.implicitHeight, closeBtn.implicitHeight)

    Row {
      id: actions
      spacing: Style.space(8)

      ActionButton {
        text: root.tr.t("panel.markRead")
        shortcut: Shortcuts.actions.markRead.label
        onClicked: root.markReadRequested()
      }

      ActionButton {
        text: root.tr.t("panel.closeAll")
        shortcut: Shortcuts.actions.closeAll.label
        onClicked: root.closeAllRequested()
      }

      ActionButton {
        text: root.tr.t("panel.clear")
        shortcut: Shortcuts.actions.clear.label
        onClicked: root.clearRequested()
      }
    }

    ActionButton {
      id: closeBtn
      anchors.right: parent.right
      text: root.tr.t("panel.close")
      shortcut: Shortcuts.closeLabel
      foreground: Util.alpha(Commons.Color.popups.text, 0.7)
      onClicked: root.dismissRequested()
    }
  }
}
