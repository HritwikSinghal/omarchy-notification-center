import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

import "Art.js" as Art

// Notes every track the MPRIS players announce -- title, artist, cover URL --
// so media rows in the history can show their cover (Art.js). It lives in the
// panel, which the shell keeps loaded (manifest keepLoaded), so it hears each
// track whether or not the panel is open.
//
// A player's metadata settles in steps: tidal-hifi publishes the new title
// first and the cover a beat later, so recording on the first change would
// pair the new title with the old cover. Each player's change restarts a
// short timer and only the settled state is recorded.
Item {
  id: root

  property var entries: []
  property bool loaded: false
  readonly property int settleMs: 1500
  readonly property string cachePath:
    Quickshell.env("HOME") + "/.cache/gabodev.notification-center/art.json"

  function note(player) {
    if (!player) return
    var next = Art.record(root.entries, {
      title: player.trackTitle,
      artist: player.trackArtist,
      art: player.trackArtUrl
    }, Date.now() / 1000)
    if (next === root.entries) return
    root.entries = next
    if (root.loaded) saveTimer.restart()
  }

  Instantiator {
    model: Mpris.players

    delegate: QtObject {
      id: watcher
      required property var modelData

      property Timer settle: Timer {
        interval: root.settleMs
        onTriggered: root.note(watcher.modelData)
      }

      property Connections changes: Connections {
        target: watcher.modelData
        function onTrackTitleChanged() { watcher.settle.restart() }
        function onTrackArtistChanged() { watcher.settle.restart() }
        function onTrackArtUrlChanged() { watcher.settle.restart() }
      }

      Component.onCompleted: watcher.settle.restart()
    }
  }

  // Tracks heard before the file loads are kept, newest first, ahead of it.
  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.finishLoad(cacheFile.text())
    onLoadFailed: root.finishLoad("")
  }

  function finishLoad(text) {
    if (root.loaded) return
    var stored = Art.parse(text)
    var merged = root.entries
    for (var i = stored.length - 1; i >= 0; i--)
      merged = Art.record(merged, stored[i], stored[i].ts)
    // record() puts each one first; restore newest-first order by time.
    merged = merged.slice().sort(function(a, b) { return b.ts - a.ts })
    root.entries = merged
    root.loaded = true
    if (merged.length > 0) saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 2000
    onTriggered: cacheFile.setText(Art.serialise(root.entries))
  }

  Component.onDestruction: {
    if (root.loaded && saveTimer.running) {
      saveTimer.stop()
      cacheFile.setText(Art.serialise(root.entries))
    }
  }
}
