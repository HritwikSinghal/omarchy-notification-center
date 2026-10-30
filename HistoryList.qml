import QtQuick
import qs.Commons
import qs.Commons as Commons

import "Fonts.js" as Fonts
import "History.js" as History

// The scrolling history and the empty state that stands in for it. Whole rows
// only: a list that ends mid-row reads as a bug.
Column {
  id: root

  required property var tr
  property var rows: []
  property real lastSeen: 0

  readonly property real rowHeight: Style.space(78)
  readonly property real headerHeight: Style.space(32)
  // What the empty state says: the panel swaps in "no matches" while searching.
  property string emptyText: ""
  // Tallest the list may grow; the panel sets it from the screen height.
  property real maxHeight: Style.space(480)

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

  // The keyboard selection, an index into `items`; -1 when nothing is
  // selected. The panel drives it from the search line's keys. When rows go
  // away it stays on the same slot, which now holds the next row.
  property int currentIndex: -1
  readonly property bool hasSelection: root.currentIndex >= 0 && root.currentIndex < root.shownCount
  onShownCountChanged: if (root.currentIndex >= root.shownCount) root.select(root.shownCount - 1)

  function select(index) {
    root.currentIndex = index
    if (index >= 0) list.positionViewAtIndex(index, ListView.Contain)
  }

  function clearSelection() { root.currentIndex = -1 }

  // Down from nothing selects the first row, Up from nothing the last.
  function moveSelection(delta) {
    if (root.shownCount === 0) return
    if (!root.hasSelection) root.select(delta > 0 ? 0 : root.shownCount - 1)
    else root.select(Math.max(0, Math.min(root.shownCount - 1, root.currentIndex + delta)))
  }

  function selectedRow() {
    return root.hasSelection ? root.items[root.currentIndex].row : null
  }

  function activateSelected() {
    var row = root.selectedRow()
    if (row) root.activated(row)
  }

  function dismissSelected() {
    var row = root.selectedRow()
    if (row) root.removeRequested(String(row.key || ""))
  }

  function dismissSelectedGroup() {
    var row = root.selectedRow()
    if (row) root.dismissGroup(History.appKey(row))
  }

  // Every row of a group, collapsed ones included, not just those drawn.
  function dismissGroup(key) {
    var keys = []
    for (var i = 0; i < root.grouped.length; i++) {
      var row = root.grouped[i].row
      if (History.appKey(row) === key && row.key) keys.push(String(row.key))
    }
    if (keys.length > 0) root.removeGroupRequested(keys)
  }

  function toggleGroup(key) {
    var next = root.collapsed.slice()
    var at = next.indexOf(key)
    if (at < 0) next.push(key)
    else next.splice(at, 1)
    root.collapsed = next
  }

  // Left collapses the selected row's group, Right expands it. Collapsing
  // moves the selection to the group's surviving row, which leads it.
  function setSelectedGroupCollapsed(collapse) {
    var row = root.selectedRow()
    if (!row) return
    var key = History.appKey(row)
    if ((root.collapsed.indexOf(key) >= 0) === collapse) return
    root.toggleGroup(key)
    for (var i = 0; i < root.shownCount; i++) {
      if (root.items[i].groupStart && History.appKey(root.items[i].row) === key) {
        root.select(i)
        return
      }
    }
  }

  // Wheel distance in pixels: one mouse notch (120 units) moves ten rows;
  // touchpad pixel deltas are scaled 16x. Flickable's own wheel handling moved
  // a fraction of a row per notch. The touchpad gain also makes up for
  // Hyprland's touchpad scroll_factor 0.5, which halves the deltas before they
  // arrive. Both tuned up by feel, from 1.5 rows / 2x.
  readonly property real notchPixels: root.rowHeight * 10
  readonly property real touchpadGain: 16

  signal activated(var entry)
  signal removeRequested(string key)
  signal removeGroupRequested(var keys)

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
      text: root.emptyText !== "" ? root.emptyText : root.tr.t("panel.empty")
      color: Util.alpha(Commons.Color.popups.text, 0.6)
      font.family: Fonts.text
      font.pixelSize: Style.font.subtitle
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }
  }

  ListView {
    id: list
    width: parent.width
    // As many whole entries as fit under maxHeight, each with its group header
    // if it opens one, so the list never ends mid-row. Always at least one.
    height: {
      var total = 0
      for (var i = 0; i < root.shownCount; i++) {
        var next = total + root.rowHeight + (root.items[i].groupStart ? root.headerHeight : 0) + Style.space(2)
        if (i > 0 && next - Style.space(2) > root.maxHeight) break
        total = next
      }
      return Math.max(0, total - Style.space(2))
    }
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

      // Group header: chevron, app, count, and a close for the whole group.
      // Clicking anywhere else on it collapses the group.
      Item {
        width: parent.width
        height: root.headerHeight
        visible: entry.item.groupStart === true

        // First, so the close button declared after it sits on top.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleGroup(entry.groupKey)
        }

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
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: String(entry.row.app || entry.row.source || root.tr.t("panel.otherApp"))
            color: Util.alpha(Commons.Color.popups.text, 0.8)
            font.family: Fonts.text
            font.pixelSize: Style.font.body
            font.bold: true
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: String(entry.item.groupSize || 0)
            color: Util.alpha(Commons.Color.popups.text, 0.45)
            font.family: Fonts.text
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        DismissButton {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.dismissGroup(entry.groupKey)
        }
      }

      NotificationRow {
        width: parent.width
        rowHeight: root.rowHeight
        tr: root.tr
        row: entry.row
        isUnread: Number(entry.row.ts || 0) > root.lastSeen
        selected: entry.index === root.currentIndex

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
