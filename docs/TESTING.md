# Testing

**TL;DR**

```sh
tests/run.sh                      # unit tests, a few seconds, no desktop needed
tests/e2e/smoke.py /tmp/nce-out   # end to end on a hidden desktop, about a minute
```

Then look at `/tmp/nce-out/*.png` against the checklist below. Both commands exit
non-zero on failure. Neither touches the real desktop, its notifications or its
history, so they are safe to run unattended, including from Claude Code.

## Unit tests (`tests/run.sh`)

| Suite | Covers | Runner |
|---|---|---|
| `tests/js/history.test.mjs` | `History.js`: view state, new / unread, `enteredAt`, clear, undo, grouping, Expand all, search | `node --test` |
| `tests/js/shortcuts-images.test.mjs` | `Shortcuts.js` key table; `Images.js` row-to-image matching and path checks | `node --test` |
| `tests/py/test_capture.py` | `capture/notify-capture.py`: downscale, PNG output, file copying, cache pruning and size cap, call/reply pairing | `unittest` (pytest also runs it) |

`tests/js/load.mjs` loads a `.pragma library` file the way QML does. Objects it
returns come from another JS context: compare them with `plain()` (JSON), not
`deepStrictEqual`.

The suites were checked by mutation testing: small deliberate bugs, each of
which must make a test fail. When adding logic, add the test that would catch
its most likely bug, and check it fails on a broken copy before trusting it.

## End to end (`tests/e2e/`)

`tests/e2e/nce` runs a hidden, isolated Omarchy desktop:

- its own `XDG_RUNTIME_DIR`, so its Wayland, Hyprland and shell sockets are its
  own, and `hyprctl` / `omarchy-shell` run through `nce run` can only reach it;
- its own D-Bus session bus, so `notify-send` reaches the Omarchy notification
  daemon inside it, which writes a fixture history;
- its own `HOME`, with `tests/e2e/fixtures/shell.json` (only this plugin in the
  bar; lock and idle off) and this repository's working tree linked in as the
  plugin, so uncommitted changes are what gets tested;
- a nested Hyprland (`tests/e2e/hyprland.lua`) drawing to a 1920x1080 headless
  output named `E2E`. Its window on the real desktop is switched off.

Requirements: a running Hyprland session, `qs` with `OMARCHY_PATH` set, `wtype`,
`grim`, `dbus-run-session`, `python3`.

### The smoke test

`tests/e2e/smoke.py [OUTPUT_DIR]` starts a session, sends 12 notifications (one
app with 7 tracks and covers, so Expand all has something to cut), then walks
every feature with real key presses and checks the plugin's own state
(`omarchy-shell notification-center state`) after each step, polling rather
than sleeping. It stops the session when done. Its log is
`OUTPUT_DIR/nce.log`; each check prints `ok` or `FAIL` with the last state.

### Screenshot checklist

| File | Must show |
|---|---|
| `01-open-all-new.png` | Panel top-right under the bar; three groups; every row with the accent bar, stronger fill and bold title; "N new" on group headers and the header pill; tidal-hifi rows with their coloured covers and a small app badge; the bell in the bar with a count |
| `02-one-new-row.png` | Only the "One more thing" Chat row has the bar and bold title; the other rows have only the unread dot; pill reads "1 new . 12 unread" |
| `03-removed-undo-line.png` | One row fewer; footer line "Removed 1 notification. Ctrl+Z to undo" |
| `04-cleared-undo-line.png` | Empty list text; panel still open; "Cleared 12 notifications. Ctrl+Z to undo" |
| `05-search.png` | Only "Invoice due" under Mail; "invoice" in the search field |
| `06-expand-all.png` | tidal-hifi shows 5 of its 7 rows; "Expand all" button lit |
| `07-collapse-all.png` | Each group shows its header and newest row only |
| every shot | Footer fits on one line with each shortcut under its button; nothing clipped |

## Driving it by hand

```sh
tests/e2e/nce up &                 # Claude Code: run_in_background instead of &
tests/e2e/nce wait
tests/e2e/nce run notify-send -a Mail "Subject" "Body"
tests/e2e/nce run omarchy-shell shell toggle gabodev.notification-center '{"anchorX":100000}'
tests/e2e/nce run wtype -k Down                      # a key
tests/e2e/nce run wtype -M ctrl e -m ctrl            # Ctrl+E
tests/e2e/nce run wtype -M ctrl -M shift e -m shift -m ctrl
tests/e2e/nce state                                  # JSON, see below
tests/e2e/nce shot /tmp/panel.png
tests/e2e/nce down
```

`state` reports `opened`, `history` (all / visible / shown), `view` (lastSeen,
lastOpened, clearedAt, hidden, unread, fresh = new), `search`, `undo` (steps,
footer text), `list` (items, selectedKey, expandAll, collapsed) and `capture`
(helper running, images). The session's logs are in `$TMPDIR/nce-current/`:
`hyprland.log`, `shell.log` (the plugin's `[nc:...]` lines appear after
`nce run omarchy-shell notification-center debug on`).

## Traps

- A Unix socket path may not exceed 108 bytes, so the session directory sits
  directly in `$TMPDIR` with a short name. A long `TMPDIR` breaks Hyprland
  startup ("socket path ... exceeds 108 bytes").
- `HYPRLAND_INSTANCE_SIGNATURE` from the real session must not leak into the
  nested one; `nce` sets the nested signature in its env file.
- `omarchy-shell -q` suppresses output; never pipe its `-q` form into a check.
- Hyprland in Lua config mode takes Lua dispatchers: `hyprctl dispatch exit`
  fails, `hyprctl dispatch 'hl.dsp.exit()'` works (that is what `nce down` runs).
- Never reuse a session across code changes: it runs the code it loaded at
  `nce up`. `smoke.py` refuses to start while another session is up.
- A notification reaches the history only when its popup closes (a few
  seconds after `notify-send`, whatever `-t` asks), so wait on
  `history.all`, not on time.
- Mark all read (Ctrl+M) closes the panel; reopen it before the next key.
- Collapse state lives as long as the shell. After Collapse all, only toggling
  groups open shows rows again, so a script must test removals first.
- The nested shell logs pipewire, polkit and portal warnings; they are expected.
  The plugin listed as `active: false` is normal too.

## Not covered

Mouse clicks (no pointer tool is installed), animation timing, and the
Spanish interface are checked by neither suite.
