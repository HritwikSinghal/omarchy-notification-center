#!/usr/bin/env python3
"""End-to-end smoke test on a hidden desktop (tests/e2e/nce).

Starts its own isolated session, sends real notifications through Omarchy's
daemon inside it, drives the panel with real key presses (wtype) and checks
the plugin's own state (omarchy-shell notification-center state) after each
step. Screenshots of the visual milestones go to the output directory for a
person, or Claude, to look at; see docs/TESTING.md for what each should show.

    tests/e2e/smoke.py [OUTPUT_DIR]

Exits 0 when every check passes, 1 otherwise. Never touches the real desktop.
"""

import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
NCE = os.path.join(HERE, "nce")
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="nce-smoke.")
os.makedirs(OUT, exist_ok=True)

failures = []


def nce(*args, check=True):
    return subprocess.run([NCE, *args], check=check, capture_output=True, text=True).stdout


def state():
    return json.loads(nce("state"))


def key(*args):
    """One wtype call, e.g. key("-k", "Down") or key("-M", "ctrl", "e", "-m", "ctrl")."""
    nce("run", "wtype", *args)


def ctrl(letter, shift=False):
    if shift:
        key("-M", "ctrl", "-M", "shift", letter, "-m", "shift", "-m", "ctrl")
    else:
        key("-M", "ctrl", letter, "-m", "ctrl")


def until(what, predicate, timeout=8.0):
    """Polls state until predicate(state) holds; records a failure otherwise."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = state()
            if predicate(last):
                print(f"ok    {what}")
                return last
        except (subprocess.CalledProcessError, ValueError, KeyError, TypeError):
            pass  # no answer yet, or a field missing: keep polling, then fail
        time.sleep(0.15)
    failures.append(what)
    print(f"FAIL  {what}\n      last state: {json.dumps(last)[:600]}")
    return last


def shot(name):
    path = os.path.join(OUT, name)
    time.sleep(0.4)  # let the 180 ms row and drop-down animations settle
    nce("shot", path)
    print(f"shot  {path}")


def png(path, rgb):
    """A 64x64 solid PNG, standard library only."""
    raw = b"".join(b"\x00" + bytes(rgb) * 64 for _ in range(64))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def notify(app, title, body, image=None):
    args = ["run", "notify-send", "-a", app, "-t", "500"]
    if image:
        args += ["-h", f"string:image-path:{image}"]
    nce(*args, title, body)


def toggle():
    nce("run", "omarchy-shell", "shell", "toggle", "gabodev.notification-center", '{"anchorX":100000}')


def open_panel(what):
    """Opens the panel and waits until keys reach it: focus moves to the
    search line a moment after `opened`, and a key sent before then is lost."""
    toggle()
    return until(what, lambda s: s["opened"] and s["keyFocus"])


def items(s):
    return s["list"]["items"]


def main():
    # A session someone else started would run old code and hold old state.
    current = os.path.join(os.environ.get("TMPDIR") or "/tmp", "nce-current")
    if os.path.exists(os.path.join(current, "ready")):
        print(f"smoke: a session is already up ({os.path.realpath(current)}); run `tests/e2e/nce down` first",
              file=sys.stderr)
        return 2
    up = subprocess.Popen([NCE, "up"], stdout=open(os.path.join(OUT, "nce.log"), "w"), stderr=subprocess.STDOUT)
    try:
        nce("wait", "60")
        if up.poll() is not None:
            print("smoke: nce up exited early; see nce.log", file=sys.stderr)
            return 2
        run_scenario()
    finally:
        nce("down", check=False)
        try:
            up.wait(timeout=15)
        except subprocess.TimeoutExpired:
            print("warn  session did not stop within 15 s", file=sys.stderr)
    print(f"\n{'PASS' if not failures else 'FAIL'}: {len(failures)} failed check(s); screenshots in {OUT}")
    for what in failures:
        print(f"  - {what}")
    return 1 if failures else 0


def run_scenario():
    # Notifications land in history only when their popup closes, so wait for
    # the daemon to write them all. Seven from one app exceed the 5-row preview.
    for i, title in enumerate(["Invoice due", "Team lunch", "Build passed"]):
        notify("Mail", title, f"mail body {i}")
    notify("Chat", "Ana", "Are we still on?")
    for i in range(7):
        cover = os.path.join(OUT, f"cover{i}.png")
        png(cover, (40 + 30 * i, 80, 200 - 20 * i))
        notify("tidal-hifi", f"Track {i}", "Artist", image=cover)
    until("all 11 notifications reach the history", lambda s: s["history"]["all"] == 11, timeout=30)
    until("the helper captured the 7 covers", lambda s: s["capture"]["images"] >= 7)
    until("the bell counts all 11 as new", lambda s: s["view"]["fresh"] == 11)

    open_panel("panel opens")
    until("it lists every row", lambda s: items(s) == 11)
    shot("01-open-all-new.png")

    # Closing the panel makes them seen; a later arrival is new on its own.
    toggle()
    until("closing stamps lastOpened: nothing new", lambda s: not s["opened"] and s["view"]["fresh"] == 0)
    notify("Chat", "Ana", "One more thing")
    until("a notification after the close is new", lambda s: s["view"]["fresh"] == 1, timeout=30)
    open_panel("panel reopens")
    shot("02-one-new-row.png")

    # Mark all read (Ctrl+M) closes the panel and clears unread and new.
    ctrl("m")
    until("Ctrl+M marks all read and closes", lambda s: not s["opened"] and s["view"]["unread"] == 0)
    open_panel("panel reopens after mark read")

    # Removal and undo, from the keyboard. Groups run newest first: Chat (it
    # got the last message), tidal-hifi, Mail; 12 rows in all.
    until("every row shown", lambda s: items(s) == 12)
    key("-k", "Down")
    until("Down selects the first row", lambda s: s["list"]["selectedKey"] != "")
    key("-k", "Delete")
    until("Delete removes the selected row", lambda s: s["view"]["hidden"] == 1 and s["undo"]["steps"] == 1)
    until("the footer offers the undo", lambda s: "Ctrl+Z" in s["undo"]["footer"])
    shot("03-removed-undo-line.png")
    ctrl("z")
    until("Ctrl+Z brings the row back", lambda s: s["view"]["hidden"] == 0 and s["undo"]["steps"] == 0)
    key("-M", "shift", "-k", "Delete", "-m", "shift")
    until("Shift+Delete removes the whole Chat group", lambda s: s["view"]["hidden"] == 2)
    ctrl("z")
    until("Ctrl+Z brings the group back", lambda s: s["view"]["hidden"] == 0 and items(s) == 12)

    ctrl("l")
    until("Ctrl+L clears and keeps the panel open", lambda s: s["opened"] and s["history"]["visible"] == 0)
    shot("04-cleared-undo-line.png")
    ctrl("z")
    until("Ctrl+Z undoes the clear", lambda s: s["history"]["visible"] == 12)

    key("invoice")
    until("search filters to the match", lambda s: s["search"] == "invoice" and items(s) == 1)
    shot("05-search.png")
    key("-k", "Escape")
    until("Esc clears the search, panel stays", lambda s: s["search"] == "" and s["opened"])

    # Expand all: nothing is unread now, so tidal-hifi shows its newest 5 of 7.
    ctrl("e")
    until("Ctrl+E expands all with a 5-row preview", lambda s: s["list"]["expandAll"] and items(s) == 2 + 5 + 3)
    shot("06-expand-all.png")
    key("-k", "Tab")
    key("-k", "Tab")
    until("Tab twice reaches the tidal-hifi group", lambda s: s["list"]["selectedKey"] != "")
    key("-k", "Right")
    until("Right on a previewed group shows all of it", lambda s: items(s) == 2 + 7 + 3)
    key("-k", "Left")
    until("Left folds the group", lambda s: items(s) == 2 + 1 + 3)
    key("-k", "Right")
    until("unfolding by hand shows every row", lambda s: items(s) == 2 + 7 + 3)
    ctrl("e", shift=True)
    until("Ctrl+Shift+E collapses every group", lambda s: not s["list"]["expandAll"] and items(s) == 3)
    shot("07-collapse-all.png")
    ctrl("e")
    until("Ctrl+E from collapsed shows the previews", lambda s: s["list"]["expandAll"] and items(s) == 2 + 5 + 3)
    ctrl("e")
    until("a second Ctrl+E shows every row", lambda s: s["list"]["expandFull"] and items(s) == 2 + 7 + 3)
    shot("08-expand-full.png")
    ctrl("e")
    until("a third Ctrl+E goes back to the previews",
          lambda s: s["list"]["expandAll"] and not s["list"]["expandFull"] and items(s) == 2 + 5 + 3)

    # Esc steps back: the selection, then the panel.
    key("-k", "Escape")
    key("-k", "Escape")
    until("Esc closes the panel", lambda s: not s["opened"])


if __name__ == "__main__":
    sys.exit(main())
