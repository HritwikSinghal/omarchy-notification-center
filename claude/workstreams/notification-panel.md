---
name: notification-panel
description: Notification history panel -- this fork of the gabodev.notification-center Omarchy/Quickshell plugin: search, app groups, keyboard nav, Ctrl shortcuts, undo stack, new-since-open highlight, expand/collapse all, captured notification images (bus-monitor helper), card-sized window for 240Hz, GPLv3 relicense; plus the parked "live notifications with app action buttons" (mail Delete / Mark read) decision
status: active, 2.0.0 shipped (resume point at top); live action buttons PARKED 2026-10-31
---

# Notification history panel

## Resume point (2026-10-31, end of session)
Release 2.0.0 at `6a82570`, installed and loaded; `bd1ce09` and earlier are pushed,
`6a82570` (and this tracker update) are not. Licence GPL-3.0-or-later; upstream's MIT
notice kept in LICENSE.MIT for code through 7ec034b. User-facing behaviour is documented
in README.md and CHANGELOG.md (2.0.0); this file keeps only what those don't.

State of the work:
- Features: app groups, search, keyboard nav, footer shortcuts from one table
  (Shortcuts.js; Ctrl+M/D/L, Ctrl+E cycles preview -> every row -> preview, Ctrl+Shift+E
  collapse, Esc), undo stack for every removal (History.undoHide), NEW tier by
  `lastOpened`, captured notification images (capture/notify-capture.py, 160px thumbs,
  200 MB cap), bell counts NEW only.
- Tests: `tests/run.sh` = 60 unit tests (32 JS, 28 Python), mutation score 92/94 (the 2
  survivors: an equivalent mutant, and main() not calling expire(), which only a live
  busctl run reaches). `tests/e2e/smoke.py OUT` = 31 checks + 8 screenshots on the hidden
  desktop (`tests/e2e/nce`); last run all pass and screenshots reviewed. Runbook and
  screenshot checklist: `docs/TESTING.md`.
- Bugs fixed today, by the bug-finder pass (`82d8032`) and by the new tests (`6a82570`):
  see CHANGELOG "Fixed" and the commit bodies. Not in the changelog: the helper's
  pending-image race, malformed bus messages, `file://` decoding, safeImage `..`, int pixel
  data.

Next:
1. Push `6a82570` and the tracker commit when the maintainer says so.
2. Optional: e2e coverage for the Spanish interface (Omarchy language file) and mouse
   clicks (needs a pointer tool such as wlrctl; none installed).
3. Parked: live action buttons (below).

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
- Tests: `tests/run.sh` (node --test for History/Shortcuts/Images, unittest for the
  helper; mutation-audited 2026-10-31) and `tests/e2e/smoke.py OUT` (hidden isolated
  desktop via `tests/e2e/nce`: private runtime dir + D-Bus + HOME, nested Hyprland on a
  headless E2E output, real Omarchy shell and daemon, wtype keys, grim shots). Runbook,
  screenshot checklist and traps: `docs/TESTING.md`. Run both before calling a change done.

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
