---
name: notification-panel
description: Notification history panel -- this fork of the gabodev.notification-center Omarchy/Quickshell plugin: search, app groups, keyboard nav, Ctrl shortcuts, undo stack, new-since-open highlight, expand/collapse all, captured notification images (bus-monitor helper), card-sized window for 240Hz, GPLv3 relicense; plus the parked "live notifications with app action buttons" (mail Delete / Mark read) decision
status: active (resume point at top); live action buttons PARKED 2026-10-31
---

# Notification history panel

## Resume point (2026-10-31)
Plugin code `82d8032` installed and loaded (not pushed; `0322629` is).
Licence is GPL-3.0-or-later (LICENSE); upstream's MIT notice is kept in LICENSE.MIT for
code through 7ec034b. Built on top of upstream 7ec034b:
- Group by app (collapsible, animated by row height), search, keyboard nav (arrows by row,
  Tab by group, Enter, Delete / Shift+Delete, Left/Right fold, Esc steps back), round close
  buttons on rows and groups, Adwaita Sans type scale (Fonts.js), card-sized window,
  drop-down open/close, debug logging + IPC (Debug.js).
- Every notification's own image via a bus-monitor helper (capture/notify-capture.py,
  Images.js, ImageCapture.qml); raw image-data is box-filtered to 160px (a 1280px cover:
  2.3 MB -> 44 KB, 0.11 s). Verified on real rows: tidal-hifi covers and omasnap screenshots.
- Footer shortcuts; one table in Shortcuts.js drives both the keys and the hint under each
  button: Ctrl+M mark read, Ctrl+D close all, Ctrl+L clear, Ctrl+E expand all (toggle;
  newest 5 per group or all its unread), Ctrl+Shift+E collapse all, Esc close. Handled in
  SearchField's Keys.onPressed, where focus always sits.
- Undo stack (Ctrl+Z, 10 s after the last action) for every removal: Delete, Shift+Delete,
  row/group close, Clear history, Close all. History.undoHide reverses only what one step
  changed. Clear / Close all keep the panel open so the undo line is seen.
- NEW tier: rows after `lastOpened` (stamped on panel close) or `lastSeen`, whichever is
  later: accent bar + stronger fill + bold title, "N new" on group headers and the header
  pill; the bell badge counts NEW only.
- The MPRIS track-cover cache (Art.js / ArtRecorder.qml) was removed: tidal-hifi sends its
  cover as image-data, which the capture helper keeps.

- Bug-finder pass over `7ec034b..357e06d` (2026-10-31), fixed in `82d8032`: image cleanup
  deleting a pending call's image (reproduced, fixed, re-run passes); new/unread/clear
  judged by arrival `ts` although a row enters history at popup close (now `enteredAt` =
  max(ts, closed_ts)); folds moving the selection into another group; malformed bus
  messages crashing the helper; `file://` URLs not percent-decoded; no byte cap on the
  cache (now 200 MB); ImageCapture ignoring XDG_CACHE_HOME. Under Expand all, unfolding
  a group by hand (header or Right) shows all its rows.

Next:
1. Visual check of the loaded build: NEW highlight, expand/collapse incl. unfolding one
   group fully, undo line, Spanish footer fit.
2. Push 82d8032 when the maintainer says so.
3. CHANGELOG.md and manifest.json still say upstream's 1.0.0 / gabodev; a 2.0.0 entry
   is suggested, not agreed.
4. Parked: live action buttons (below).

Debugging: `omarchy-shell notification-center debug on|off` (persisted in
`~/.config/omarchy/gabodev.notification-center/debug`), `omarchy-shell notification-center
state` (JSON). Log lines are `[nc:<area>]` in `$XDG_RUNTIME_DIR/quickshell/by-id/*/log.log`.
Toggling debug restarts the capture helper, which logs "helper exited with 15" (SIGTERM) --
expected, not a fault.

## Where things live
- Upstream: `GaboEI/omarchy-notification-center` (remote `upstream`), forked at 7ec034b.
- Installed: `~/.config/omarchy/plugins/gabodev.notification-center/`, a git clone of this
  fork. Load local commits without pushing: `git -C <installed> fetch <this repo> main &&
  git -C <installed> merge --ff-only FETCH_HEAD`, then restart the shell (plugin hot-reload
  does not apply edits). Run the restart through Hyprland
  (`hyprctl eval 'hl.exec_cmd("omarchy restart shell")'`) when the caller's process tree may
  be reaped, e.g. from a sandboxed tool session. `omarchy plugin update
  gabodev.notification-center` pulls the pushed fork.
- Opening by key: `omarchy-shell shell toggle gabodev.notification-center '{"anchorX":100000}'`
  pins the card top-right. Hyprland layer rules can target the namespaces
  `gabodev-notification-center` (the card) and `gabodev-notification-center-catcher`.
- Data: reads Omarchy's `~/.local/state/omarchy/notifications/history.json` only (100 rows /
  24h, closed notifications only; images never stored). Own files: view state in
  `~/.config/omarchy/gabodev.notification-center/config.json` (lastSeen, lastOpened,
  clearedAt, hidden), captured images in `~/.cache/gabodev.notification-center/images/` +
  `images.json` (48h, 300 entries).
- Image capture: the helper runs `busctl --user monitor org.freedesktop.Notifications
  --json=short` (works unprivileged on the session bus), pairs each Notify call with the
  daemon's reply by (call sender + cookie) = (reply destination + reply_cookie); the reply's
  id equals the history row's `originalId`. Ids restart at 1 on every shell restart, so
  rows match on id + app + time within 60s.
- Tests: none in the repo yet. History.js and Shortcuts.js are `.pragma library` files that
  load in node after stripping the pragma line; the helper's pure functions import in python.

## Things learned
- Frame rate: a full-screen 4K layer animated at 93-121fps on a 240Hz monitor; a 680x1620
  card-sized layer at 235-238fps (probe, 3 runs each; blur+dim cost ~3fps). Qt itself is fine
  (threaded render loop, vsync animation driver 4.17ms). Hence the card has its own window
  and a static full-screen catcher (Top layer) handles click-outside.
- Third-party plugins get a facade of the notifications service with only DND
  (`/usr/share/omarchy/shell/services/PluginFirstPartyServiceApi.qml`): no live notifications,
  no `invokeAction`. `omarchy-shell notifications invokeAction <n>` only hits the newest card.
- A notification sent with `--transient` never reaches history: the daemon keeps transient
  ones out of its store (`Service.qml` storePut).
- Qt's Keys: specific handlers (onUpPressed, ...) run before onPressed; letters have none,
  so Ctrl+letter shortcuts land in onPressed, and Keys runs before TextInput's own editing.
  Ctrl+E is TextInput's end-of-line on Linux; the panel takes it over (End still works).
- The panel reads config.json once (`watchChanges: false`); edit the file only with the shell
  stopped or followed by a restart, or the panel writes its in-memory copy back over it.
- Opening the panel takes exclusive keyboard focus: keystrokes typed meanwhile land in its
  search field, so never open it from a script while someone is typing.

## PARKED: live notifications with app action buttons
Buttons like a mail client's Delete / Mark read are freedesktop actions; they only work while
the sender still holds the notification. Omarchy closes it when its popup times out, and the
facade gives plugins no access, so the panel cannot offer them.

Options (decision open):
- **Minimal patch (recommended)**: fork `omarchy.notifications` with only ~30-60 lines in
  `Service.qml` -- hide a timed-out popup instead of closing the notification, and expose the
  live list + `invokeAction` to our panel. Panel stays a separate plugin.
- File upstream (omacom/omarchy) for live notifications + invokeAction on the plugin facade;
  then only the keep-open behaviour (or nothing) stays local.
- Full fork with the panel inside, or our own daemon on `Quickshell.Services.Notifications`:
  most work; the own-daemon route must re-implement `omarchy-shell notifications` IPC.

Upstream churn of `shell/plugins/notifications` (omacom/omarchy, measured 2026-10-31, path
exists since 2026-05-18; plugin ~3,300 lines, Service.qml 1,658):

| Month | Commits | +lines / -lines |
|---|---|---|
| 2026-05 | 27 | +2015 / -362 |
| 2026-06 | 4 | +114 / -49 |
| 2026-07 | 8 | +82 / -465 |
| 2026-08 | 16 | +1173 / -723 |
| 2026-09 | 4 | +64 / -2 |
| 2026-10 | 61 | +11641 / -10209 (near-rewrite, 42 commits on Oct 19-20) |

A full fork would need a hand merge most months; the minimal patch keeps that small.
