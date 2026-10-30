import QtQuick
import qs.Commons
import qs.Commons as Commons

// The round close button on rows and group headers: a multiplication sign on a
// circle that fills on hover, large enough to hit without aiming.
Rectangle {
  id: root

  // Dimmed until hovered, or until its row is the keyboard selection.
  property bool emphasised: false

  signal clicked()

  width: Style.space(26)
  height: width
  radius: width / 2
  color: hover.hovered
    ? Util.alpha(Commons.Color.popups.text, 0.14)
    : "transparent"

  Behavior on color {
    ColorAnimation {
      duration: 90
    }
  }

  Text {
    anchors.centerIn: parent
    // U+00D7 multiplication sign, written escaped to keep the file ASCII.
    text: "\u00d7"
    color: hover.hovered || root.emphasised
      ? Commons.Color.popups.text
      : Util.alpha(Commons.Color.popups.text, 0.45)
    font.family: Style.font.family
    font.pixelSize: Style.font.display
    textFormat: Text.PlainText
  }

  HoverHandler {
    id: hover
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
