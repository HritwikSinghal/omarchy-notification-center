import QtQuick
import qs.Commons
import qs.Commons as Commons

import "History.js" as History

// The scrolling history and the empty state that stands in for it. Whole rows
// only: a list that ends mid-row reads as a bug.
Column {
  id: root

  required property var tr
  property var rows: []
  property real lastSeen: 0

  readonly property real rowHeight: Style.space(68)
  readonly property real headerHeight: Style.space(24)
  readonly property int maxVisibleRows: 6

  // Rows grouped by app (History.groupByApp). A collapsed group keeps its
  // header and newest row. Collapse state lives only as long as the panel.
  property var collapsed: []
  readonly property var grouped: History.groupByApp(root.rows)
  readonly property var items: {
    var out = []
    for (var i = 0; i < root.grouped.length && out.length < 100; i++) {
      var item = root.grouped[i]
      if (item.groupStart || root.collapsed.indexOf(History.appKey(item.row)) < 0) out.push(item)
    }
    return out
  }
  readonly property int shownCount: root.items.length

  function toggleGroup(key) {
    var next = root.collapsed.slice()
    var at = next.indexOf(key)
    if (at < 0) next.push(key)
    else next.splice(at, 1)
    root.collapsed = next
  }

  // Wheel distance in pixels: one mouse notch (120 units) moves about one and
  // a half rows; touchpad pixel deltas are doubled. Flickable's own wheel
  // handling moved a fraction of a row per notch.
  readonly property real notchPixels: root.rowHeight * 1.5
  readonly property real touchpadGain: 2

  signal activated(var entry)
  signal removeRequested(string key)

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  // Empty state
  Column {
    width: parent.width
    visible: root.rows.length === 0
    spacing: Style.space(6)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "\uf0f3"
      color: Util.alpha(Commons.Color.popups.text, 0.25)
      font.family: Style.font.family
      font.pixelSize: Style.space(28)
      textFormat: Text.PlainText
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.tr.t("panel.empty")
      color: Util.alpha(Commons.Color.popups.text, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }
  }

  ListView {
    id: list
    width: parent.width
    height: Math.min(root.shownCount, root.maxVisibleRows) * (root.rowHeight + Style.space(2)) - Style.space(2)
    visible: root.rows.length > 0
    clip: true
    model: root.shownCount
    spacing: Style.space(2)
    boundsBehavior: Flickable.StopAtBounds

    delegate: Column {
      id: entry
      required property int index
      readonly property var item: root.items[index] || ({ row: {}, groupStart: false, groupSize: 0 })
      readonly property var row: entry.item.row || ({})
      readonly property string groupKey: History.appKey(entry.row)
      readonly property bool groupCollapsed: root.collapsed.indexOf(entry.groupKey) >= 0

      width: list.width

      // Group header: chevron, app, count. Clicking it collapses the group.
      Item {
        width: parent.width
        height: root.headerHeight
        visible: entry.item.groupStart === true

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            // nf-fa chevron_right / chevron_down
            text: entry.groupCollapsed ? "\uf054" : "\uf078"
            color: Util.alpha(Commons.Color.popups.text, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: String(entry.row.app || entry.row.source || root.tr.t("panel.otherApp"))
            color: Util.alpha(Commons.Color.popups.text, 0.8)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: String(entry.item.groupSize || 0)
            color: Util.alpha(Commons.Color.popups.text, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleGroup(entry.groupKey)
        }
      }

      NotificationRow {
        width: parent.width
        rowHeight: root.rowHeight
        tr: root.tr
        row: entry.row
        isUnread: Number(entry.row.ts || 0) > root.lastSeen

        onActivated: root.activated(entry.row)
        onRemoveRequested: root.removeRequested(String(entry.row.key || ""))
      }
    }

    // Wheel only: no buttons, so clicks and hover still reach the rows.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function(wheel) {
        var dy = wheel.pixelDelta.y !== 0
          ? wheel.pixelDelta.y * root.touchpadGain
          : wheel.angleDelta.y / 120 * root.notchPixels
        var top = list.originY
        var bottom = Math.max(top, list.originY + list.contentHeight - list.height)
        list.contentY = Math.max(top, Math.min(bottom, list.contentY - dy))
        wheel.accepted = true
      }
    }
  }
}
