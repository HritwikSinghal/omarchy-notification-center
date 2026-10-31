import QtQuick
import Quickshell
import Quickshell.Io

import "Debug.js" as Debug
import "Images.js" as Images

// Runs capture/notify-capture.py, which keeps the images notifications carry
// (Omarchy's history drops them), and holds its index for rows to look up
// (Images.js). The panel stays loaded, so this runs whether or not the panel
// is open. The helper prints each new record on stdout; its index file is read
// once at start. If it exits, it is started again after a growing pause.
Item {
  id: root

  property var entries: []
  property bool debug: false
  readonly property bool running: helper.running
  property int restarts: 0
  property string lastError: ""

  // The same cache directory the helper picks: XDG_CACHE_HOME, else ~/.cache.
  readonly property string indexPath:
    (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
      + "/gabodev.notification-center/images.json"
  readonly property string scriptPath:
    decodeURIComponent(String(Qt.resolvedUrl("capture/notify-capture.py")).replace(/^file:\/\//, ""))

  function start() {
    helper.environment = { "NC_DEBUG": root.debug ? "1" : "0" }
    helper.running = true
    Debug.log("capture", "helper started", root.scriptPath)
  }

  // A changed debug setting reaches the helper through its environment.
  onDebugChanged: if (helper.running) helper.running = false

  Process {
    id: helper
    command: ["python3", "-I", root.scriptPath]

    stdout: SplitParser {
      onRead: function(line) {
        var record
        try { record = JSON.parse(line) } catch (error) {
          Debug.warn("capture", "unreadable helper line", line.slice(0, 200))
          return
        }
        var next = Images.add(root.entries, record)
        if (next === root.entries) {
          Debug.warn("capture", "rejected record", record)
          return
        }
        root.entries = next
        Debug.log("capture", "image for id", record.id, record.app, record.image)
      }
    }

    stderr: SplitParser {
      onRead: function(line) {
        if (/^(warn|error):/.test(line)) {
          root.lastError = line
          Debug.warn("capture", line)
        } else {
          Debug.log("capture", line)
        }
      }
    }

    onExited: function(code) {
      root.restarts += 1
      // 2s, 4s, 8s ... capped at a minute, so a broken helper cannot spin.
      restartTimer.interval = Math.min(60000, 2000 * Math.pow(2, Math.min(5, root.restarts - 1)))
      Debug.log("capture", "helper exited", code, "restart in", restartTimer.interval, "ms")
      if (code !== 0) Debug.warn("capture", "helper exited with", code, root.lastError)
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    onTriggered: root.start()
  }

  // A helper that has stayed up a while resets the backoff.
  Timer {
    interval: 120000
    running: helper.running
    onTriggered: root.restarts = 0
  }

  FileView {
    id: indexFile
    path: root.indexPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.entries = Images.parse(indexFile.text())
      Debug.log("capture", "index loaded", root.entries.length, "images")
    }
  }

  Component.onCompleted: root.start()
}
