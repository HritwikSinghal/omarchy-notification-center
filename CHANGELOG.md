# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-10-31

First release of this fork. Licensed GPL-3.0-or-later from here on; upstream's
MIT notice is kept in `LICENSE.MIT`.

### Added

- Rows grouped by app, with collapsible group headers that close a whole group.
- Search by app, title or body.
- Keyboard control: arrows by row, Tab by group, Enter, Delete / Shift+Delete,
  Left / Right to fold, Esc steps back through selection, search and panel.
- Footer shortcuts written under each button: Ctrl+M mark all read, Ctrl+D close
  all, Ctrl+L clear history, Ctrl+E expand all (first press: newest 5 rows per group,
  or all its unread; second: every row; then it switches between the two),
  Ctrl+Shift+E collapse all, Esc close.
- Undo for every removal (row, group, Clear history, Close all) with Ctrl+Z for
  10 seconds; the footer says what was removed.
- A "new" tier: rows that reached the history since the panel last closed get an
  accent bar, a stronger fill and a bold title, and the bell counts only them.
- The image a notification carried (a screenshot, an album cover) on its row,
  saved by a small helper that watches the session bus; raw pixels are shrunk to a
  thumbnail.
- `omarchy-shell notification-center state` and `debug on|off` for debugging.

### Changed

- The panel hangs in its own card-sized window, drops down on open and animates
  collapse, expand and removal; larger type in a sans face.
- Clear history and Close all keep the panel open so the undo line can be read.
- New and unread are judged by when a notification entered the history, so one
  whose popup was still on screen is not counted as seen.

### Fixed

- The keyboard selection follows its notification instead of its slot, so Enter
  and Delete never act on a row that slid into its place; after a removal it
  stays in the same app group, even when the removal reorders the groups.
- On a first run the bell ignored every read, close and clear until the shell
  restarted: its settings file did not exist yet, so nothing watched it.

## [1.0.0] - 2026-10-27

### Added

- A bell in the bar with an unread count that reads correctly at any number,
  including `99+`.
- A notification history panel that opens under the bell and follows it when it
  is moved along the bar.
- Per-row removal, mark all read, close all, and clear history.
- Row activation: run a saved notification action, focus the app that sent it,
  open its website, or launch a verified desktop app.
- Right-click Do Not Disturb with a red crossed bell, kept in sync with
  Omarchy's own setting.
- Spanish and English interface, following the desktop language.

### Notes

- Clearing the panel hides entries from the panel only. Omarchy keeps its own
  notification history and exposes no way to erase it.
- A notification that has expired cannot reopen the exact chat or browser tab;
  the plugin focuses or launches the app instead and says so when it cannot.
