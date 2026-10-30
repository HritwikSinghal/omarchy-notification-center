import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

import "Fonts.js" as Fonts

// One notification: hover and unread fills, the unread dot, the app thumbnail,
// the metadata and text, the relative time, and the per-row close. It reads the
// row it is given and reports gestures; it never acts on one itself.
Rectangle {
  id: rowItem

  required property var tr
  property var row: ({})
  property bool isUnread: false
  property real rowHeight: Style.space(78)

  // The app's icon: the notification's own app_icon when it sent one (a path
  // or a theme name), else the icon of the desktop entry its app name matches.
  // Omarchy's history rarely carries app_icon, so the lookup does most of the
  // work. "" when neither resolves; the tile then shows the row's glyph.
  readonly property string iconSource: {
    var icon = String(rowItem.row.appIcon || "")
    if (icon === "") {
      var name = String(rowItem.row.app || "")
      var entry = name !== "" ? DesktopEntries.heuristicLookup(name) : null
      icon = entry ? String(entry.icon || "") : ""
    }
    if (icon === "") return ""
    if (icon.charAt(0) === "/") return "file://" + icon
    if (/^(file|image):\/\//.test(icon)) return icon
    return Quickshell.iconPath(icon, true)
  }

  signal activated()
  signal removeRequested()

  // Relative time, in the reader's language.
  function ago(ts) {
    var t = Number(ts || 0);
    if (t <= 0)
      return "";
    var d = Math.max(0, Date.now() / 1000 - t);
    if (d < 60)
      return root.tr.t("time.now");
    if (d < 3600)
      return root.tr.t("time.minutes").arg(Math.trunc(d / 60));
    if (d < 86400)
      return root.tr.t("time.hours").arg(Math.trunc(d / 3600));
    return root.tr.t("time.days").arg(Math.trunc(d / 86400));
  }

  // The keyboard selection: an accent fill and outline, stronger than hover.
  property bool selected: false

  width: parent ? parent.width : 0
  height: rowHeight
  radius: Style.space(3)
  color: rowItem.selected
         ? Util.alpha(Commons.Color.accent, 0.16)
         : rowHover.hovered
           ? Util.alpha(Commons.Color.popups.text, 0.06)
           : (rowItem.isUnread ? Util.alpha(Commons.Color.accent, 0.07) : "transparent")
  border.width: rowItem.selected ? 1 : 0
  border.color: Util.alpha(Commons.Color.accent, 0.6)

  Behavior on color {
    ColorAnimation {
      duration: 90
    }
  }

  HoverHandler {
    id: rowHover
  }

  // Resolving the target is the panel's job: this only reports the gesture.
  MouseArea {
    anchors.fill: parent
    onClicked: rowItem.activated()
  }

  // Unread dot
  Rectangle {
    id: dot
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.top: parent.top
    anchors.topMargin: Style.space(14)
    width: Style.space(5)
    height: width
    radius: width / 2
    color: Commons.Color.accent
    visible: rowItem.isUnread
  }

  // App thumbnail: the app's icon, else the row's glyph (or a bell) on a tile.
  Rectangle {
    id: thumb
    anchors.left: dot.right
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(36)
    height: width
    radius: Style.space(6)
    color: icon.status === Image.Ready ? "transparent" : Util.alpha(Commons.Color.popups.text, 0.08)

    Image {
      id: icon
      anchors.fill: parent
      source: rowItem.iconSource
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      visible: status === Image.Ready
    }

    Text {
      anchors.centerIn: parent
      visible: icon.status !== Image.Ready
      text: String(rowItem.row.glyph || "\uf0f3")
      color: Util.alpha(Commons.Color.popups.text, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      textFormat: Text.PlainText
    }
  }

  Column {
    id: rowCol
    anchors.left: thumb.right
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(40)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: appText.implicitHeight

      Text {
        id: appText
        anchors.left: parent.left
        anchors.right: timeText.left
        anchors.rightMargin: Style.space(8)
        text: String(rowItem.row.app || rowItem.row.source || "")
        color: Util.alpha(Commons.Color.popups.text, 0.6)
        font.family: Fonts.text
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        id: timeText
        anchors.right: parent.right
        text: rowItem.ago(rowItem.row.ts)
        color: Util.alpha(Commons.Color.popups.text, 0.5)
        font.family: Fonts.text
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
    }

    Text {
      width: parent.width
      text: String(rowItem.row.summary || "")
      color: Commons.Color.popups.text
      font.family: Fonts.text
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
      wrapMode: Text.WordWrap
      maximumLineCount: 1
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }

    Text {
      width: parent.width
      visible: String(rowItem.row.body || "") !== ""
      text: String(rowItem.row.body || "")
      color: Util.alpha(Commons.Color.popups.text, 0.8)
      font.family: Fonts.text
      font.pixelSize: Style.font.subtitle
      wrapMode: Text.WordWrap
      maximumLineCount: 1
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
  }

  // Per-row close
  DismissButton {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.top: parent.top
    anchors.topMargin: Style.space(6)
    emphasised: rowItem.selected
    onClicked: rowItem.removeRequested()
  }
}
