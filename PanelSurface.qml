import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Card chrome for the notification panel: the border, the unread hairline, the
// drop-down motion and Esc. The panel hands its parts in through `content`, in
// the order they stack; this file holds no data and no state.
//
// It fills a window only as large as the card (Panel.qml cardWin), not the
// whole screen: on a 4K output a full-screen surface repainted every animated
// frame held the panel to 120fps or less on a 240Hz screen, while a card-sized
// one keeps up. Where that window sits on screen is worked out here
// (cardScreenX, cardScreenTop) from the screen it opens on.
Item {
  id: root

  property bool opened: false
  property int unread: 0
  // Screen x the card centres on: the bar widget that opened it. -1 keeps the
  // old screen-centred placement used by a keybind or menu summon.
  property real anchorX: -1

  readonly property real cardWidth: Style.space(660)
  readonly property real edgeMargin: Style.space(12)

  // The screen the panel opens on, in its own logical pixels.
  property real screenWidth: 0
  property real screenHeight: 0
  // Where the card's window goes on that screen, hung under the bar. The
  // window starts dropDistance above the card so the drop-in is not clipped.
  readonly property real cardScreenX: root.cardX(root.screenWidth)
  readonly property real cardScreenTop: Style.bar.sizeHorizontal + Style.space(8)
  readonly property real maxCardHeight: Math.max(0, root.screenHeight - Style.space(96))
  // Fixed while open: resizing a layer surface every animated frame would
  // cost more than it saves.
  readonly property real windowHeight: root.maxCardHeight + root.dropDistance
  // The card itself, for the window's input mask.
  readonly property Item cardItem: card

  // Open drops the card down from above while it fades in; close lifts it
  // back. The panel keeps the window mapped for `motionDuration` after close
  // so the lift is seen (Panel.qml closeHold).
  readonly property int motionDuration: 220
  readonly property real dropDistance: Style.space(40)

  // Hung from the bell: its centre is the card's centre, pulled in only when
  // that would push the card past a screen edge. Centred with no anchor.
  function cardX(available) {
    var centred = (available - cardWidth) / 2
    if (!(root.anchorX > 0))
      return centred
    var wanted = root.anchorX - cardWidth / 2
    var limit = Math.max(edgeMargin, available - cardWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(wanted, limit))
  }
  // Ordered by the list the panel passes: each item joins the column in that
  // order, which is what decides the vertical stack.
  property list<Item> content

  signal dismissed()

  function grabFocus() {
    keyCatcher.forceActiveFocus();
  }

  function placeContent() {
    for (var i = 0; i < root.content.length; i++)
      if (root.content[i])
        root.content[i].parent = col;
  }

  onContentChanged: root.placeContent()
  Component.onCompleted: root.placeContent()

  BorderSurface {
    id: card
    // The window is placed on screen (cardScreenX/Top); in it the card sits
    // at the left, dropDistance down.
    x: 0
    y: root.dropDistance
    width: root.cardWidth
    height: Math.min(root.maxCardHeight,
                     card.borderTop + Style.spacing.panelPadding + col.implicitHeight + Style.spacing.panelPadding + card.borderBottom)
    color: Commons.Color.popups.background
    radius: Style.cornerRadius
    borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border, Commons.Color.popups.border, Math.max(1, Style.space(2)))

    opacity: root.opened ? 1 : 0
    Behavior on opacity {
      NumberAnimation {
        duration: root.motionDuration
        easing.type: Easing.OutCubic
      }
    }

    transform: Translate {
      y: root.opened ? 0 : -root.dropDistance
      Behavior on y {
        NumberAnimation {
          duration: root.motionDuration
          easing.type: Easing.OutCubic
        }
      }
    }

    // Clicks on the card are not clicks outside it.
    MouseArea {
      anchors.fill: parent
    }

    // A hair of accent along the top edge while something is unread: the
    // one cue that reads at a glance from across the room.
    Rectangle {
      anchors.top: parent.top
      anchors.topMargin: card.borderTop
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.max(0, parent.width - 2 * card.borderLeft)
      height: Style.space(2)
      color: Util.alpha(Commons.Color.accent, root.unread > 0 ? 0.55 : 0)
      Behavior on color {
        ColorAnimation {
          duration: 160
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismissed()
    }

    Column {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: card.borderLeft + Style.spacing.panelPadding
      anchors.rightMargin: card.borderRight + Style.spacing.panelPadding
      anchors.topMargin: card.borderTop + Style.spacing.panelPadding
      spacing: Style.spacing.panelGap
    }
  }
}
