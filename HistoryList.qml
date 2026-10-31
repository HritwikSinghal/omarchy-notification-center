import QtQuick
import qs.Commons
import qs.Commons as Commons

import "Fonts.js" as Fonts
import "Debug.js" as Debug
import "History.js" as History
import "Images.js" as Images

// The scrolling history and the empty state that stands in for it. Whole rows
// only: a list that ends mid-row reads as a bug.
Column {
  id: root

  required property var tr
  property var rows: []
  property real lastSeen: 0
  // Rows after this arrived since the panel last closed: drawn as new, and
  // counted on their group's header.
  property real newSince: 0
  readonly property var newByApp: History.countByApp(root.rows, root.newSince)
  readonly property var unreadByApp: History.countByApp(root.rows, root.lastSeen)

  readonly property real rowHeight: Style.space(88)
  readonly property real headerHeight: Style.space(36)
  // Images notifications carried (ImageCapture); a row's own image wins.
  property var imageEntries: []
  // What the empty state says: the panel swaps in "no matches" while searching.
  property string emptyText: ""
  // Tallest the list may grow; the panel sets it from the screen height.
  property real maxHeight: Style.space(480)

  // Rows grouped by app (History.groupByApp). A collapsed group keeps its
  // header and newest row. Collapse state lives only as long as the panel.
  property var collapsed: []
  // Expand all (Ctrl+E): every group open, but showing only its newest
  // previewRows rows, or all its unread ones when there are more. Toggling it
  // off restores the collapse state it replaced.
  property bool expandAll: false
  property var collapsedBeforeExpand: []
  // Groups unfolded by hand (header or Right) while Expand all is on: these
  // show every row instead of the preview. Reset whenever Expand all is
  // toggled or everything is collapsed.
  property var fullGroups: []
  readonly property int previewRows: 5
  readonly property var grouped: History.groupByApp(root.rows)
  readonly property var items: History.shownItems(root.grouped, root.collapsed, root.expandAll,
                                                  root.fullGroups, root.unreadByApp,
                                                  root.previewRows, 100)
  readonly property int shownCount: root.items.length

  // The view's model holds only each shown row's key, kept in step with
  // `items` by syncModel() as inserts, moves and removals rather than a reset,
  // so ListView can animate rows in and out (collapse, expand, dismiss,
  // search). Delegates look their row up by key. A row without a key, or a
  // repeated one, gets a positional stand-in; such rows just do not animate.
  readonly property var itemKeys: {
    var out = [], seen = new Set()
    for (var i = 0; i < root.items.length; i++) {
      var key = String((root.items[i].row && root.items[i].row.key) || "")
      if (key === "" || seen.has(key)) key = "row-" + i
      seen.add(key)
      out.push(key)
    }
    return out
  }
  readonly property var itemByKey: {
    var map = new Map()
    for (var i = 0; i < root.itemKeys.length; i++) map.set(root.itemKeys[i], root.items[i])
    return map
  }

  ListModel {
    id: rowModel
  }

  function syncModel() {
    var removed = 0, moved = 0, inserted = 0
    var target = root.itemKeys
    var wanted = new Set(target)
    for (var i = rowModel.count - 1; i >= 0; i--)
      if (!wanted.has(rowModel.get(i).key)) {
        rowModel.remove(i)
        removed++
      }
    for (var j = 0; j < target.length; j++) {
      if (j < rowModel.count && rowModel.get(j).key === target[j]) continue
      var at = -1
      for (var k = j + 1; k < rowModel.count; k++) {
        if (rowModel.get(k).key === target[j]) {
          at = k
          break
        }
      }
      if (at >= 0) {
        rowModel.move(at, j, 1)
        moved++
      } else {
        rowModel.insert(j, { key: target[j] })
        inserted++
      }
    }
    while (rowModel.count > target.length) rowModel.remove(rowModel.count - 1)
    if (rowModel.count !== target.length) Debug.warn("list", "model out of step", rowModel.count, "vs", target.length)
    Debug.log("list", "sync", { rows: target.length, removed: removed, moved: moved, inserted: inserted })
  }

  onItemKeysChanged: {
    root.syncModel()
    root.followSelection()
  }
  Component.onCompleted: root.syncModel()

  // Row motion: arrivals fade in, departures fade out, the rest slide.
  readonly property int motionDuration: 180

  // The keyboard selection: the selected notification's key, and its index in
  // `items` (-1 when nothing is selected). The panel drives it from the search
  // line's keys. It follows the notification, not the slot: a new notification
  // that moves its group to the top must not leave Enter or Delete aimed at
  // whatever row slid into the old position. Only when the selected row itself
  // goes away (dismissed, collapsed) does it fall back to the same slot, which
  // now holds the next row.
  property string selectedKey: ""
  property int currentIndex: -1
  readonly property bool hasSelection: root.currentIndex >= 0 && root.currentIndex < root.shownCount

  function select(index) {
    if (index < 0 || index >= root.shownCount) {
      root.clearSelection()
      return
    }
    root.currentIndex = index
    root.selectedKey = root.itemKeys[index]
    Debug.log("list", "select", index, root.selectedKey)
    list.positionViewAtIndex(index, ListView.Contain)
  }

  function clearSelection() {
    root.selectedKey = ""
    root.currentIndex = -1
  }

  function followSelection() {
    if (root.selectedKey === "") return
    var at = root.itemKeys.indexOf(root.selectedKey)
    if (at >= 0) root.select(at)
    else root.select(Math.min(root.currentIndex, root.shownCount - 1))
  }

  // Down from nothing selects the first row, Up from nothing the last.
  function moveSelection(delta) {
    if (root.shownCount === 0) return
    if (!root.hasSelection) root.select(delta > 0 ? 0 : root.shownCount - 1)
    else root.select(Math.max(0, Math.min(root.shownCount - 1, root.currentIndex + delta)))
  }

  // Tab and Shift+Tab: the first row of the next or previous group. From no
  // selection, the first or the last group. Stops at either end.
  function moveGroup(delta) {
    var starts = []
    for (var i = 0; i < root.shownCount; i++)
      if (root.items[i].groupStart) starts.push(i)
    if (starts.length === 0) return
    if (!root.hasSelection) {
      root.select(delta > 0 ? starts[0] : starts[starts.length - 1])
      return
    }
    // The group the selection is in: the last start at or before it.
    var at = 0
    for (var j = 0; j < starts.length; j++)
      if (starts[j] <= root.currentIndex) at = j
    root.select(starts[Math.max(0, Math.min(starts.length - 1, at + (delta > 0 ? 1 : -1)))])
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

  // A fold can hide the selected row, and followSelection would then fall
  // back to its slot, which may now hold another group (Shift+Delete would
  // hit that group). Keep the selection in its own group instead: on the row
  // if it is still shown, else on the group's first row, which every fold
  // keeps.
  function keepSelectionInGroup(change) {
    var row = root.selectedRow()
    var key = root.selectedKey
    change()
    if (!row) return
    var at = root.itemKeys.indexOf(key)
    if (at >= 0) {
      root.select(at)
      return
    }
    var group = History.appKey(row)
    for (var i = 0; i < root.shownCount; i++) {
      if (root.items[i].groupStart && History.appKey(root.items[i].row) === group) {
        root.select(i)
        return
      }
    }
  }

  function toggleExpandAll() {
    root.keepSelectionInGroup(function() {
      root.fullGroups = []
      if (root.expandAll) {
        root.expandAll = false
        root.collapsed = root.collapsedBeforeExpand
        return
      }
      root.collapsedBeforeExpand = root.collapsed
      root.collapsed = []
      root.expandAll = true
    })
  }

  // Every group down to its header and newest row; ends Expand all.
  function collapseAll() {
    root.keepSelectionInGroup(function() {
      var keys = []
      for (var i = 0; i < root.grouped.length; i++)
        if (root.grouped[i].groupStart) keys.push(History.appKey(root.grouped[i].row))
      root.fullGroups = []
      root.expandAll = false
      root.collapsed = keys
    })
  }

  // Unfolding a group by hand under Expand all shows all of it, not the
  // preview: folding and unfolding is how one group gets its full list back.
  function toggleGroup(key) {
    root.keepSelectionInGroup(function() {
      var next = root.collapsed.slice()
      var at = next.indexOf(key)
      var full = root.fullGroups.filter(function(k) { return k !== key })
      if (at < 0) {
        next.push(key)
      } else {
        next.splice(at, 1)
        if (root.expandAll) full.push(key)
      }
      root.fullGroups = full
      root.collapsed = next
    })
  }

  // Left collapses the selected row's group, Right expands it. Collapsing
  // moves the selection to the group's surviving row, which leads it.
  // Under Expand all, Right on a group still showing its preview shows all of
  // it. toggleGroup keeps the selection in the group.
  function setSelectedGroupCollapsed(collapse) {
    var row = root.selectedRow()
    if (!row) return
    var key = History.appKey(row)
    var isCollapsed = root.collapsed.indexOf(key) >= 0
    if (!collapse && !isCollapsed && root.expandAll && root.fullGroups.indexOf(key) < 0) {
      root.keepSelectionInGroup(function() { root.fullGroups = root.fullGroups.concat([key]) })
      return
    }
    if (isCollapsed === collapse) return
    root.toggleGroup(key)
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
      font.pixelSize: Fonts.px(Style.font.body, Fonts.body)
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
    // The card resizes with the rows instead of jumping.
    Behavior on height {
      NumberAnimation {
        duration: root.motionDuration
        easing.type: Easing.OutCubic
      }
    }
    visible: root.rows.length > 0
    clip: true
    model: rowModel
    spacing: Style.space(2)
    boundsBehavior: Flickable.StopAtBounds

    // Rows arrive and leave by animating their own height (`reveal`), not by
    // ListView's add/remove/displaced transitions: the view re-lays itself
    // out every frame as heights change, so no row can be left stranded
    // mid-move. Those transitions did exactly that when interrupted or when a
    // group header appeared mid-animation, stacking rows on top of each other.
    delegate: Item {
      id: entry
      required property int index
      required property string key
      // The row as last looked up. A departing delegate's key is gone from
      // itemByKey, so it keeps what it last showed while it fades out.
      readonly property var lookup: root.itemByKey.get(entry.key)
      property var item: ({ row: {}, groupStart: false, groupSize: 0 })
      onLookupChanged: if (entry.lookup) entry.item = entry.lookup
      Component.onCompleted: if (entry.lookup) entry.item = entry.lookup
      readonly property var row: entry.item.row || ({})
      readonly property string groupKey: History.appKey(entry.row)
      readonly property bool groupCollapsed: root.collapsed.indexOf(entry.groupKey) >= 0

      // 0 = collapsed out of the list, 1 = fully shown.
      property real reveal: 1

      width: list.width
      height: content.implicitHeight * entry.reveal
      opacity: entry.reveal
      clip: entry.reveal < 1

      ListView.onAdd: arrive.start()
      ListView.onRemove: leave.start()

      NumberAnimation {
        id: arrive
        target: entry
        property: "reveal"
        from: 0
        to: 1
        duration: root.motionDuration
        easing.type: Easing.OutCubic
      }

      // delayRemove keeps the delegate alive until it has folded away.
      SequentialAnimation {
        id: leave
        PropertyAction { target: entry; property: "ListView.delayRemove"; value: true }
        NumberAnimation {
          target: entry
          property: "reveal"
          to: 0
          duration: root.motionDuration
          easing.type: Easing.OutCubic
        }
        PropertyAction { target: entry; property: "ListView.delayRemove"; value: false }
      }

      Column {
        id: content
        width: parent.width

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
              // nf-fa chevron_down, turned to point right while collapsed.
              text: "\uf078"
              rotation: entry.groupCollapsed ? -90 : 0
              Behavior on rotation {
                NumberAnimation {
                  duration: root.motionDuration
                  easing.type: Easing.OutCubic
                }
              }
              color: Util.alpha(Commons.Color.popups.text, 0.45)
              font.family: Style.font.family
              font.pixelSize: Fonts.px(Style.font.body, Fonts.meta)
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: String(entry.row.app || entry.row.source || root.tr.t("panel.otherApp"))
              color: Util.alpha(Commons.Color.popups.text, 0.8)
              font.family: Fonts.text
              font.pixelSize: Fonts.px(Style.font.body, Fonts.meta)
              font.bold: true
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: String(entry.item.groupSize || 0)
              color: Util.alpha(Commons.Color.popups.text, 0.45)
              font.family: Fonts.text
              font.pixelSize: Fonts.px(Style.font.body, Fonts.small)
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              readonly property int fresh: root.newByApp[entry.groupKey] || 0
              visible: fresh > 0
              text: root.tr.t("panel.new").arg(Commons.I18n.formatNumber(fresh))
              color: Commons.Color.accent
              font.family: Fonts.text
              font.pixelSize: Fonts.px(Style.font.body, Fonts.small)
              font.bold: true
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
          isUnread: History.enteredAt(entry.row) > root.lastSeen
          isNew: History.enteredAt(entry.row) > root.newSince
          imageUrl: Images.lookup(root.imageEntries, entry.row)
          // A row folding away is never the selection, whatever index Qt gives it.
          selected: entry.lookup !== undefined && entry.index === root.currentIndex

          onActivated: root.activated(entry.row)
          onRemoveRequested: root.removeRequested(String(entry.row.key || ""))
        }
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
