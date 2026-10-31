import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import qs.Ui

import "Debug.js" as Debug
import "History.js" as History
import "Shortcuts.js" as Shortcuts

// gabodev.notification-center panel: the notification history Omarchy keeps,
// which its own UI only shows as transient toasts.
//
// This file owns the data and the gestures: the live service and its fallback
// file, the local view state and its persistence, navigation, and what each
// action does. The card itself is composed from PanelSurface, HistoryHeader,
// HistoryList, NotificationRow and PanelFooter, which draw what they are told.
//
// Anchored under the bar and centred, the way a dropdown reads, instead of
// covering the middle of the screen. Rows come from the first-party
// notifications service (`historyEntries`, newest first), filtered by what
// this panel hides: `clearedAt` drops everything older than the last clear,
// `hidden` drops single entries.
Item {
  id: root

  property bool opened: false
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "gabodev.notification-center"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/gabodev.notification-center/config.json"
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history.json"

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Navigator {
    id: navigator
  }

  // Images notifications carried, which Omarchy's history drops; every row
  // whose notification had one shows it (ImageCapture, Images.js).
  ImageCapture {
    id: imageCapture
    debug: root.debugEnabled
  }

  // ------------------------------------------------------------- debugging
  // Debug.js logs to the shell log while this is on. The setting survives
  // restarts in a one-line file; IPC flips it and dumps live state:
  //   omarchy-shell notification-center debug on|off
  //   omarchy-shell notification-center state
  property bool debugEnabled: false
  onDebugEnabledChanged: {
    Debug.enabled = root.debugEnabled
    console.log("[nc:panel] debug " + (root.debugEnabled ? "on" : "off"))
  }
  readonly property string debugPath:
    Quickshell.env("HOME") + "/.config/omarchy/gabodev.notification-center/debug"

  FileView {
    id: debugFile
    path: root.debugPath
    watchChanges: false
    printErrors: false
    onLoaded: root.debugEnabled = debugFile.text().trim() === "1"
  }

  function stateDump() {
    return JSON.stringify({
      opened: root.opened,
      anchorX: root.anchorX,
      debug: root.debugEnabled,
      history: { source: (root.notifService && root.notifService.historyLoaded) ? "service" : "file",
                 all: root.allEntries.length, visible: root.entries.length,
                 shown: root.shownEntries.length, loadFailed: root.historyLoadFailed },
      view: { lastSeen: root.lastSeen, lastOpened: root.lastOpened, clearedAt: root.clearedAt,
              hidden: Object.keys(root.hidden || {}).length, unread: root.unread, fresh: root.fresh },
      search: root.query,
      keyFocus: searchField.inputFocused,
      undo: { steps: root.undoStack.length, footer: root.undoText },
      list: { items: historyList.shownCount, selectedKey: historyList.selectedKey,
              expandAll: historyList.expandAll, expandFull: historyList.expandFull,
              currentIndex: historyList.currentIndex, collapsed: historyList.collapsed },
      capture: { running: imageCapture.running, images: imageCapture.entries.length,
                 restarts: imageCapture.restarts, lastError: imageCapture.lastError,
                 script: imageCapture.scriptPath }
    }, null, 2)
  }

  Commons.ShellIpc {
    target: "notification-center"

    function state(): string { return root.stateDump() }

    function debug(value: string): string {
      var v = String(value || "").toLowerCase()
      var on = v === "on" || v === "1" || v === "true" || v === "yes"
      root.debugEnabled = on
      debugFile.setText(on ? "1\n" : "0\n")
      return on ? "on" : "off"
    }
  }
  readonly property var notifService: (root.shell && root.shell.firstPartyServiceFor)
    ? root.shell.firstPartyServiceFor("omarchy.notifications")
    : null

  // Rows from the live service, else the last successful read of its state
  // file. A native atomic rewrite can briefly fail to parse; never turn that
  // race into an empty panel.
  property var fallbackRows: []
  readonly property var allEntries: {
    var service = root.notifService
    if (service && service.historyLoaded)
      return Array.isArray(service.historyEntries) ? service.historyEntries : []
    return root.fallbackRows;
  }

  // Local view state, persisted.
  property double lastSeen: 0
  // When the panel last closed; rows after it are new (History.newSince).
  property double lastOpened: 0
  property double clearedAt: 0
  property var hidden: ({})
  property bool configReady: false
  property bool historyLoadFailed: false
  property bool configDirty: false
  property var pendingStateActions: []

  property string navigationFeedback: ""

  // Removals that Ctrl+Z can still take back, oldest first: a row (Delete or
  // its close), a group (Shift+Delete or its close), or every row (Clear
  // history, Close all). Each is { before, after, count, kind }. The stack
  // empties undoWindow after the last removal or undo; the footer names the
  // newest entry and the key.
  property var undoStack: []
  readonly property int undoWindow: 10000
  readonly property int undoLimit: 20
  readonly property var lastUndo: root.undoStack.length > 0 ? root.undoStack[root.undoStack.length - 1] : null
  readonly property string undoText: root.lastUndo
    ? strings.tn(root.lastUndo.kind === "cleared" ? "panel.cleared" : "panel.removed", root.lastUndo.count)
        .arg(Commons.I18n.formatNumber(root.lastUndo.count))
        .arg(Shortcuts.actions.undo.label)
    : ""
  readonly property var entries: History.visibleRows(root.allEntries, root.historyState())

  // The search line's text, and the rows it lets through. Footer actions still
  // act on every visible row, not just the matches.
  property string query: ""
  readonly property var shownEntries: History.filterRows(root.entries, root.query)

  readonly property int unread: History.unreadCount(root.allEntries, root.historyState())
  // Rows new since the panel last closed ("new" is reserved in JS).
  readonly property int fresh: History.newCount(root.allEntries, root.historyState())

  function historyState() {
    return { version: 2, lastSeen: root.lastSeen, lastOpened: root.lastOpened, clearedAt: root.clearedAt, hidden: root.hidden };
  }

  function applyHistoryState(state) {
    root.lastSeen = Number(state.lastSeen) || 0;
    root.lastOpened = Number(state.lastOpened) || 0;
    root.clearedAt = Number(state.clearedAt) || 0;
    root.hidden = state.hidden || ({});
  }

  function mutateHistory(change) {
    if (!root.configReady) {
      root.pendingStateActions = root.pendingStateActions.concat([change]);
      return;
    }
    root.applyHistoryState(change(root.historyState()));
    root.configDirty = true;
    configSaveTimer.restart();
  }

  function finishConfigLoad(text) {
    if (root.configReady)
      return;
    var state = History.parseConfig(text, Date.now() / 1000);
    root.applyHistoryState(state);
    root.configReady = true;
    // Canonical output upgrades v1's hidden array to the bounded v2 key map.
    root.configDirty = History.serialiseConfig(state) !== String(text || "");
    var pending = root.pendingStateActions;
    root.pendingStateActions = [];
    for (var i = 0; i < pending.length; i++)
      root.mutateHistory(pending[i]);
    if (root.configDirty && !configSaveTimer.running)
      configSaveTimer.start();
  }

  function flushConfig() {
    if (!root.configReady || !root.configDirty)
      return;
    root.configDirty = false;
    configFile.setText(History.serialiseConfig(root.historyState()));
  }

  // Screen x the panel should hang from, passed by the bar widget that opens
  // it. -1 means no anchor (keybind, menu) and keeps the centred placement.
  property real anchorX: -1

  function open(payloadJson) {
    var x = -1
    try { x = Number(JSON.parse(payloadJson || "{}").anchorX) } catch (e) { x = -1 }
    root.anchorX = isFinite(x) && x > 0 ? x : -1
    root.opened = true;
    Debug.log("panel", "open", { anchorX: root.anchorX, rows: root.entries.length, unread: root.unread });
    // Every open starts unfiltered, with the keyboard in the search line, so
    // typing searches at once and Esc still closes.
    searchField.clear();
    historyList.clearSelection();
    Qt.callLater(function () {
      if (root.opened)
        searchField.focusInput();
    });
  }

  function close() {
    Debug.log("panel", "close");
    root.opened = false;
  }

  function dismiss() {
    if (root.shell && root.shell.hide)
      root.shell.hide(root.pluginId);
    else
      root.close();
  }

  // Mark all read closes the panel: the point of pressing it is to be done
  // with the list. Clear history and Close all keep it open instead, for
  // undoWindow, so the undo line is seen and Ctrl+Z reaches the search line.
  function markRead() {
    Debug.log("panel", "mark all read");
    var rows = root.entries.slice();
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.markRead(state, rows, at); });
    root.dismiss();
  }

  // Applies a removal and remembers the view state on either side of it, so
  // undoLast can reverse just that step (History.undoHide).
  function removeUndoably(change, count, kind) {
    var before = root.historyState();
    root.mutateHistory(change);
    // A removal queued before the config loaded has no settled state to undo to.
    if (!root.configReady)
      return;
    var stack = root.undoStack.concat([{ before: before, after: root.historyState(), count: count, kind: kind }]);
    root.undoStack = stack.slice(Math.max(0, stack.length - root.undoLimit));
    undoTimer.restart();
  }

  function hideEntry(key) {
    Debug.log("panel", "hide", key);
    var k = String(key || "");
    if (k === "")
      return;
    var at = Date.now() / 1000;
    root.removeUndoably(function(state) { return History.hide(state, k, at); }, 1, "removed");
  }

  // A whole group at once: one state change and one save, not one per row.
  function hideEntries(keys) {
    Debug.log("panel", "hide group", (keys || []).length, "rows");
    var list = (keys || []).map(function(key) { return String(key || ""); })
                           .filter(function(key) { return key !== ""; });
    if (list.length === 0)
      return;
    var at = Date.now() / 1000;
    root.removeUndoably(function(state) {
      var next = state;
      for (var i = 0; i < list.length; i++)
        next = History.hide(next, list[i], at);
      return next;
    }, list.length, "removed");
  }

  // Hides every visible row, undoably.
  function clearVisible() {
    var rows = root.entries.slice();
    // Nothing to hide; a second press must not cancel the pending undo.
    if (rows.length === 0)
      return;
    var at = Date.now() / 1000;
    root.removeUndoably(function(state) { return History.clear(state, rows, at); }, rows.length, "cleared");
  }

  // Undo brings the rows back to the panel; popups Close all dismissed stay
  // dismissed.
  function closeAll() {
    Debug.log("panel", "close all");
    root.clearVisible();
    dismissAllProc.running = false;
    dismissAllProc.running = true;
  }

  function clearHistory() {
    Debug.log("panel", "clear history");
    root.clearVisible();
  }

  // Takes back the newest removal; another Ctrl+Z takes back the one before.
  // Each undo restarts the window so the next one is not rushed.
  function undoLast() {
    var record = root.lastUndo;
    if (!record)
      return;
    Debug.log("panel", "undo", record.kind, record.count, "rows");
    root.undoStack = root.undoStack.slice(0, -1);
    if (root.undoStack.length > 0)
      undoTimer.restart();
    else
      undoTimer.stop();
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.undoHide(state, record.before, record.after, at); });
  }

  // Persisted history has no live notification action or message deep link. A
  // row closes only after Navigator accepts its limited safe target.
  function showNavigationFeedback() {
    root.navigationFeedback = strings.t("panel.navigationUnavailable");
    navigationFeedbackTimer.restart();
  }

  function activateEntry(row) {
    var action = navigator.resolve(row);
    Debug.log("panel", "activate", { key: row ? row.key : "", app: row ? row.app : "", action: action.kind, ok: action.ok });
    if (!action.ok) {
      root.showNavigationFeedback();
      return;
    }

    if (action.kind === "desktop-candidate") {
      // Navigator maps this ID from a fixed alias and confirms its desktop
      // entry exists; never derive a launcher command from notification data.
      var desktopId = String(action.desktopId || "");
      if (!/^(org\.telegram\.desktop|WhatsApp|discord)$/.test(desktopId)) {
        root.showNavigationFeedback();
        return;
      }
      desktopLaunchProc.command = ["uwsm-app", "--", "gtk-launch",
                                   /\.desktop$/.test(desktopId) ? desktopId : desktopId + ".desktop"];
      desktopLaunchProc.running = false;
      desktopLaunchProc.running = true;
      return;
    }

    var result = navigator.perform(action);
    if (result.ok)
      root.dismiss();
    else
      root.showNavigationFeedback();
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.finishConfigLoad(text())
    onLoadFailed: root.finishConfigLoad("")
  }

  Timer {
    id: configSaveTimer
    interval: 180
    onTriggered: root.flushConfig()
  }

  Timer {
    id: navigationFeedbackTimer
    interval: 2100
    onTriggered: root.navigationFeedback = ""
  }

  Timer {
    id: undoTimer
    interval: root.undoWindow
    onTriggered: root.undoStack = []
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(historyFile.text());
        if (Array.isArray(data)) {
          root.fallbackRows = data;
          Debug.log("history", "loaded", data.length, "rows from history.json");
          root.historyLoadFailed = false;
        } else {
          Debug.warn("history", "history.json is not a list");
          root.historyLoadFailed = true;
        }
      } catch (error) {
        // An atomic rewrite can be caught mid-way; the next change reloads.
        Debug.log("history", "history.json unreadable this time:", String(error));
        root.historyLoadFailed = true;
      }
    }
    onLoadFailed: root.historyLoadFailed = true
  }

  Component.onDestruction: {
    configSaveTimer.stop();
    root.flushConfig();
  }

  Process {
    id: dismissAllProc
    command: ["omarchy-shell", "notifications", "dismissAll"]
  }

  Process {
    id: desktopLaunchProc
    command: ["true"]
    onExited: function(exitCode) {
      if (exitCode === 0)
        root.dismiss();
      else
        root.showNavigationFeedback();
    }
  }

  // Holds the window mapped while the card lifts away on close; without it the
  // surface vanishes the frame `opened` goes false.
  Timer {
    id: closeHold
    interval: surface.motionDuration
  }
  onOpenedChanged: {
    if (root.opened) {
      closeHold.stop();
      return;
    }
    closeHold.restart();
    // Whatever was on screen has been seen: it stops being new, and the
    // bell's count drops to what arrives from here on.
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.markOpened(state, at); });
  }

  // Two surfaces: a static, transparent full-screen catcher that only closes
  // the panel on a click outside the card, and the card in a window of its
  // own size (PanelSurface explains why). The catcher sits on the Top layer
  // and the card on Overlay, so the card is above it whichever maps first.
  // The catcher picks the screen and the card follows it there.
  OverlayWindow {
    id: win
    shown: root.opened || closeHold.running
    shownLayer: WlrLayer.Top
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "gabodev-notification-center-catcher"

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }
  }

  PanelWindow {
    id: cardWin
    visible: win.visible
    screen: win.targetScreen
    anchors {
      top: true
      left: true
    }
    margins {
      left: surface.cardScreenX
      top: surface.cardScreenTop - surface.dropDistance
    }
    implicitWidth: surface.cardWidth
    implicitHeight: surface.windowHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // Blur, dim and no_anim rules match this name (hypr/looknfeel.lua).
    WlrLayershell.namespace: "gabodev-notification-center"
    // Only the card takes input; the rest of the window passes clicks through
    // to the catcher underneath.
    mask: Region {
      item: surface.cardItem
    }

    PanelSurface {
      id: surface
      anchors.fill: parent
      screenWidth: win.targetScreen ? win.targetScreen.width : 0
      screenHeight: win.targetScreen ? win.targetScreen.height : 0
      opened: root.opened
      unread: root.unread
      anchorX: root.anchorX
      onDismissed: root.dismiss()
      content: [
        HistoryHeader {
          tr: strings
          unread: root.unread
          fresh: root.fresh
          total: root.entries.length
        },
        SearchField {
          id: searchField
          tr: strings
          hasSelection: historyList.hasSelection
          canUndo: root.undoStack.length > 0
          // A new query reshuffles the rows, so a selection would land on an
          // unrelated one; start over instead.
          onTextChanged: {
            root.query = text
            historyList.clearSelection()
          }
          onDismissRequested: root.dismiss()
          onNavigateRequested: function(delta) { historyList.moveSelection(delta) }
          onGroupNavigateRequested: function(delta) { historyList.moveGroup(delta) }
          onActivateRequested: historyList.activateSelected()
          onDeleteRequested: function(wholeGroup) { wholeGroup ? historyList.dismissSelectedGroup() : historyList.dismissSelected() }
          onCollapseRequested: function(collapse) { historyList.setSelectedGroupCollapsed(collapse) }
          onClearSelectionRequested: historyList.clearSelection()
          onShortcutPressed: function(action) {
            if (action === "markRead") root.markRead()
            else if (action === "closeAll") root.closeAll()
            else if (action === "clear") root.clearHistory()
            else if (action === "undo") root.undoLast()
            else if (action === "expandAll") historyList.toggleExpandAll()
            else if (action === "collapseAll") historyList.collapseAll()
          }
        },
        HistoryList {
          id: historyList
          tr: strings
          rows: root.shownEntries
          imageEntries: imageCapture.entries
          emptyText: root.query !== "" ? strings.t("panel.noMatches") : strings.t("panel.empty")
          lastSeen: root.lastSeen
          newSince: History.newSince(root.historyState())
          // Two thirds of the screen: tall enough to scan a day's history,
          // short enough that the header and footer stay on screen.
          maxHeight: surface.screenHeight * 0.65
          onActivated: function(entry) { root.activateEntry(entry) }
          onRemoveRequested: function(key) { root.hideEntry(key) }
          onRemoveGroupRequested: function(keys) { root.hideEntries(keys) }
        },
        PanelFooter {
          tr: strings
          feedback: root.navigationFeedback !== "" ? root.navigationFeedback : root.undoText
          showRule: root.entries.length > 0
          onMarkReadRequested: root.markRead()
          onCloseAllRequested: root.closeAll()
          onClearRequested: root.clearHistory()
          expandedAll: historyList.expandAll
          onExpandAllRequested: historyList.toggleExpandAll()
          onCollapseAllRequested: historyList.collapseAll()
          onDismissRequested: root.dismiss()
        }
      ]
    }
  }
}
