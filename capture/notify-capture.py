#!/usr/bin/env python3
"""Keep the images notifications carry, for the history panel.

Omarchy's notification daemon shows a notification's image on the live
popup but never stores it ("codes, links and images never persist",
Store.js), so its history.json only has text. This helper watches the
session bus as a monitor (`busctl --user monitor`), without replacing or
talking to the daemon, and for every Notify call that carries an image it:

- saves the image into the cache: `image-data` / `icon_data` pixels are
  written as PNG; an `image-path` / `image_path` / path-like `app_icon` file
  is copied in (so a screenshot moved or deleted later still previews), only
  if it is a regular file under MAX_FILE whose bytes look like an image;
- pairs the call with the daemon's reply, which carries the notification id
  that history.json records as `originalId`;
- records {id, app, summary, ts, image} in INDEX (newest first, bounded) and
  prints the record as one JSON line on stdout for the panel to pick up.

Diagnostics go to stderr as "level: message" lines; the panel logs them.
Standard library only. Exits when busctl exits; the panel restarts it.
"""

import hashlib
import json
import operator
import os
import struct
import subprocess
import sys
import time
import urllib.parse
import zlib

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "gabodev.notification-center")
IMAGES = os.path.join(CACHE, "images")
INDEX = os.path.join(CACHE, "images.json")
LIMIT = 300                  # index entries kept
MAX_AGE = 48 * 3600          # seconds an entry and its image are kept
MAX_FILE = 20 * 1024 * 1024  # largest image file copied in
MAX_BYTES = 200 * 1024 * 1024  # all cached images together; oldest go first
MAX_PIXELS = 4096 * 4096     # largest image-data accepted
# Longest side image-data is kept at. Rows draw images at 40px (decoded at
# 80); a track cover arrives as raw 1280x1280 RGBA, 2.3 MB once written as
# PNG, against tens of KB at this size.
THUMB = 160
PENDING_TTL = 30             # seconds a call waits for its reply
DEBUG = os.environ.get("NC_DEBUG") == "1"

MAGIC = (
    (b"\x89PNG\r\n\x1a\n", "png"),
    (b"\xff\xd8\xff", "jpg"),
    (b"GIF87a", "gif"),
    (b"GIF89a", "gif"),
    (b"BM", "bmp"),
)


def say(level, message):
    if level == "debug" and not DEBUG:
        return
    print(f"{level}: {message}", file=sys.stderr, flush=True)


def image_kind(head):
    for magic, ext in MAGIC:
        if head.startswith(magic):
            return ext
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    return ""


def store(data, ext):
    """Write bytes into IMAGES under their content hash; return a file URL."""
    os.makedirs(IMAGES, exist_ok=True)
    name = hashlib.sha1(data).hexdigest() + "." + ext
    path = os.path.join(IMAGES, name)
    if not os.path.exists(path):
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
    return "file://" + path


def downscale(raw, width, height, stride, channels, limit=THUMB):
    """Pixels box-filtered so the longer side is at most `limit`, as
    (tightly packed bytes, width, height). Each output pixel averages the
    block of input pixels it covers, so a photo shrinks without the
    sparkle of nearest-neighbour. Channels are averaged unpremultiplied,
    which can tint fully transparent edges; covers and screenshots are
    opaque."""
    span = width * channels
    if max(width, height) <= limit:
        packed = b"".join(raw[y * stride:y * stride + span] for y in range(height))
        return packed, width, height
    scale = max(width, height) / limit
    out_w = max(1, round(width / scale))
    out_h = max(1, round(height / scale))
    cols = [(x * width // out_w, max(x * width // out_w + 1, (x + 1) * width // out_w))
            for x in range(out_w)]
    out = bytearray(out_w * out_h * channels)
    for oy in range(out_h):
        y0 = oy * height // out_h
        y1 = max(y0 + 1, (oy + 1) * height // out_h)
        # The block's rows summed column by column once per output row; map
        # keeps the per-pixel work in C.
        acc = [0] * span
        for y in range(y0, y1):
            acc = list(map(operator.add, acc, raw[y * stride:y * stride + span]))
        base = oy * out_w * channels
        for ox, (x0, x1) in enumerate(cols):
            count = (y1 - y0) * (x1 - x0)
            for c in range(channels):
                out[base + ox * channels + c] = sum(acc[x0 * channels + c:x1 * channels:channels]) // count
    return bytes(out), out_w, out_h


def png_from_pixels(value):
    """image-data is (iiibiiay): width, height, rowstride, has_alpha,
    bits_per_sample, channels, data. Only 8-bit RGB(A) is accepted, and it
    is shrunk to THUMB before encoding."""
    try:
        width, height, stride, has_alpha, bits, channels, pixels = value
    except (TypeError, ValueError):
        return b""
    # The bus is open to any local process, so the struct's members are not
    # trusted to have the types the spec gives them.
    if not all(isinstance(v, int) for v in (width, height, stride, bits, channels)):
        return b""
    if bits != 8 or channels not in (3, 4) or width <= 0 or height <= 0:
        return b""
    if width * height > MAX_PIXELS or stride < width * channels:
        return b""
    try:
        raw = bytes(pixels)
    except (TypeError, ValueError):
        return b""
    if len(raw) < stride * (height - 1) + width * channels:
        return b""
    raw, width, height = downscale(raw, width, height, stride, channels)
    span = width * channels
    rows = b"".join(b"\x00" + raw[y * span:(y + 1) * span] for y in range(height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    colour = 6 if channels == 4 else 2
    header = struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


def copy_file(value):
    """A local image path (or file:// URL) copied into the cache, else ""."""
    path = str(value or "")
    if path.startswith("file:"):
        # A URL percent-encodes spaces and non-ASCII; a plain path does not.
        url = urllib.parse.urlparse(path)
        if url.netloc not in ("", "localhost"):
            return ""
        path = urllib.parse.unquote(url.path)
    if not path.startswith("/"):
        return ""  # a theme icon name, not a file
    try:
        if not os.path.isfile(path):
            say("debug", f"no such file: {path}")
            return ""
        if os.path.getsize(path) > MAX_FILE:
            say("debug", f"too large to keep: {path}")
            return ""
        with open(path, "rb") as f:
            data = f.read(MAX_FILE + 1)
    except OSError as error:
        say("debug", f"cannot read {path}: {error}")
        return ""
    kind = image_kind(data[:16])
    if not kind or len(data) > MAX_FILE:
        say("debug", f"not an image: {path}")
        return ""
    return store(data, kind)


def image_for(app_icon, hints):
    """The notification's image as a cached file URL, in the spec's order of
    precedence: image-data, image-path, app_icon, icon_data."""
    def hint(*names):
        for name in names:
            if name in hints and isinstance(hints[name], dict):
                return hints[name].get("data")
        return None

    data = hint("image-data", "image_data")
    if data is not None:
        png = png_from_pixels(data)
        if png:
            return store(png, "png")
    path = hint("image-path", "image_path")
    if path:
        url = copy_file(path)
        if url:
            return url
    url = copy_file(app_icon)
    if url:
        return url
    data = hint("icon_data")
    if data is not None:
        png = png_from_pixels(data)
        if png:
            return store(png, "png")
    return ""


def load_index():
    try:
        with open(INDEX, encoding="utf-8") as f:
            value = json.load(f)
        return value if isinstance(value, list) else []
    except (OSError, ValueError):
        return []


def save_index(entries):
    os.makedirs(CACHE, exist_ok=True)
    tmp = INDEX + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(entries, f)
        f.write("\n")
    os.replace(tmp, INDEX)


def prune(entries, now, keep=()):
    """Keep the newest entries within MAX_AGE, LIMIT and MAX_BYTES (entries
    are newest first, so the oldest go), then delete image files nothing
    refers to. `keep` names files of Notify calls still waiting for their
    reply: saved already, but not in any entry yet."""
    def recent(entry):
        try:
            return now - float(entry.get("ts", 0)) <= MAX_AGE
        except (TypeError, ValueError):
            return False

    kept, used, sizes = [], 0, {}
    for entry in entries:
        if len(kept) >= LIMIT:
            break
        if not isinstance(entry, dict) or not recent(entry):
            continue
        name = os.path.basename(str(entry.get("image", "")))
        if name not in sizes:
            try:
                sizes[name] = os.path.getsize(os.path.join(IMAGES, name))
            except OSError:
                continue  # its file is gone; the row would show a broken image
            if used + sizes[name] > MAX_BYTES:
                break
            used += sizes[name]
        kept.append(entry)
    referenced = {os.path.basename(str(e.get("image", ""))) for e in kept} | set(keep)
    try:
        for name in os.listdir(IMAGES):
            if name not in referenced and not name.endswith(".tmp"):
                os.unlink(os.path.join(IMAGES, name))
    except OSError:
        pass
    return kept


def handle(message, pending, entries):
    """One bus message: remember a Notify call that carried an image, or pair
    a reply with its call and record it. Returns the (new) index entries."""
    if not isinstance(message, dict):
        return entries
    kind = message.get("type")

    if kind == "method_call" and message.get("member") == "Notify":
        try:
            app, _replaces, app_icon, summary, _body, _actions, hints, _timeout = message["payload"]["data"]
        except (KeyError, TypeError, ValueError):
            say("warn", "Notify call with an unexpected payload")
            return entries
        hints = hints if isinstance(hints, dict) else {}
        image = image_for(app_icon, hints)
        say("debug", f"Notify from {app!r} {summary!r}: image={image or 'none'} hints={sorted(hints)}")
        if image:
            pending[(message.get("sender"), message.get("cookie"))] = (app, summary, image, time.time())

    elif kind == "method_return":
        key = (message.get("destination"), message.get("reply_cookie"))
        if key not in pending:
            return entries
        app, summary, image, _started = pending.pop(key)
        data = (message.get("payload") or {}).get("data") or []
        if not data or not isinstance(data[0], int):
            return entries
        now = time.time()
        record = {"id": data[0], "app": str(app), "summary": str(summary)[:256], "ts": now, "image": image}
        waiting = {os.path.basename(v[2]) for v in pending.values()}
        entries = prune([record] + entries, now, waiting)
        save_index(entries)
        print(json.dumps(record), flush=True)
        say("debug", f"captured id={data[0]} {app!r} -> {image}")
    return entries


def main():
    entries = prune(load_index(), time.time())
    save_index(entries)
    say("info", f"watching notifications; {len(entries)} cached images")

    pending = {}  # (sender, cookie) -> (app, summary, image, started)
    monitor = subprocess.Popen(
        ["busctl", "--user", "monitor", "org.freedesktop.Notifications", "--json=short"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    for line in monitor.stdout:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        # Any local process can put a message on the bus; one the code below
        # does not expect is skipped, never allowed to end the helper.
        try:
            entries = handle(message, pending, entries)
        except Exception as error:  # noqa: BLE001 -- see above
            say("warn", f"skipped a bus message: {error!r}")

        # Calls whose reply never came (an error, a dropped message) expire.
        now = time.time()
        for key in [k for k, v in pending.items() if now - v[3] > PENDING_TTL]:
            del pending[key]

    error = monitor.stderr.read().strip()
    say("error", f"busctl monitor exited ({monitor.wait()}): {error[:300]}")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
