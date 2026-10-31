import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import qs.Ui

import "Debug.js" as Debug
import "History.js" as History

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

  // Track covers for media rows; always running, since the panel stays loaded.
  ArtRecorder {
    id: artRecorder
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
      view: { lastSeen: root.lastSeen, clearedAt: root.clearedAt,
              hidden: Object.keys(root.hidden || {}).length, unread: root.unread },
      search: root.query,
      list: { items: historyList.shownCount, selectedKey: historyList.selectedKey,
              currentIndex: historyList.currentIndex, collapsed: historyList.collapsed },
      art: { entries: artRecorder.entries.length, loaded: artRecorder.loaded },
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
  property double clearedAt: 0
  property var hidden: ({})
  property bool configReady: false
  property bool historyLoadFailed: false
  property bool configDirty: false
  property var pendingStateActions: []

  property string navigationFeedback: ""
  readonly property var entries: History.visibleRows(root.allEntries, root.historyState())

  // The search line's text, and the rows it lets through. Footer actions still
  // act on every visible row, not just the matches.
  property string query: ""
  readonly property var shownEntries: History.filterRows(root.entries, root.query)

  readonly property int unread: History.unreadCount(root.allEntries, root.historyState())

  function historyState() {
    return { version: 2, lastSeen: root.lastSeen, clearedAt: root.clearedAt, hidden: root.hidden };
  }

  function applyHistoryState(state) {
    root.lastSeen = Number(state.lastSeen) || 0;
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

  // Every footer action also closes the panel: the point of pressing one is to
  // be done with the list, not to look at the result.
  function markRead() {
    Debug.log("panel", "mark all read");
    var rows = root.entries.slice();
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.markRead(state, rows, at); });
    root.dismiss();
  }

  function hideEntry(key) {
    Debug.log("panel", "hide", key);
    var k = String(key || "");
    if (k === "")
      return;
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.hide(state, k, at); });
  }

  // A whole group at once: one state change and one save, not one per row.
  function hideEntries(keys) {
    Debug.log("panel", "hide group", (keys || []).length, "rows");
    var list = (keys || []).map(function(key) { return String(key || ""); })
                           .filter(function(key) { return key !== ""; });
    if (list.length === 0)
      return;
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) {
      var next = state;
      for (var i = 0; i < list.length; i++)
        next = History.hide(next, list[i], at);
      return next;
    });
  }

  function closeAll() {
    Debug.log("panel", "close all");
    var rows = root.entries.slice();
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.clear(state, rows, at); });
    dismissAllProc.running = false;
    dismissAllProc.running = true;
    root.dismiss();
  }

  function clearHistory() {
    Debug.log("panel", "clear history");
    var rows = root.entries.slice();
    var at = Date.now() / 1000;
    root.mutateHistory(function(state) { return History.clear(state, rows, at); });
    root.dismiss();
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
  onOpenedChanged: if (!root.opened) closeHold.restart(); else closeHold.stop()

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
          total: root.entries.length
        },
        SearchField {
          id: searchField
          tr: strings
          hasSelection: historyList.hasSelection
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
          }
        },
        HistoryList {
          id: historyList
          tr: strings
          rows: root.shownEntries
          artEntries: artRecorder.entries
          imageEntries: imageCapture.entries
          emptyText: root.query !== "" ? strings.t("panel.noMatches") : strings.t("panel.empty")
          lastSeen: root.lastSeen
          // Two thirds of the screen: tall enough to scan a day's history,
          // short enough that the header and footer stay on screen.
          maxHeight: surface.screenHeight * 0.65
          onActivated: function(entry) { root.activateEntry(entry) }
          onRemoveRequested: function(key) { root.hideEntry(key) }
          onRemoveGroupRequested: function(keys) { root.hideEntries(keys) }
        },
        PanelFooter {
          tr: strings
          feedback: root.navigationFeedback
          showRule: root.entries.length > 0
          onMarkReadRequested: root.markRead()
          onCloseAllRequested: root.closeAll()
          onClearRequested: root.clearHistory()
          onDismissRequested: root.dismiss()
        }
      ]
    }
  }
}
