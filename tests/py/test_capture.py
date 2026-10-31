"""capture/notify-capture.py: the helper that keeps notification images.

Standard library only (unittest), so `python3 -m unittest` runs it anywhere;
pytest runs it too. Every test works in its own temporary cache directory and
never touches the session bus.
"""

import contextlib
import importlib.util
import io
import json
import os
import random
import struct
import tempfile
import time
import unittest
import urllib.parse
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "..", "..", "capture", "notify-capture.py")


def load_helper():
    spec = importlib.util.spec_from_file_location("notify_capture", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


nc = load_helper()


def decode_png(data):
    """Width, height, channels and unfiltered rows of a PNG the helper wrote
    (filter type 0 on every row, as png_from_pixels writes them)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, header = 8, b"", None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    width, height, _bits, colour = header[:4]
    channels = 4 if colour == 6 else 3
    raw = zlib.decompress(idat)
    span = width * channels
    rows = [raw[y * (span + 1) + 1:(y + 1) * (span + 1)] for y in range(height)]
    return width, height, channels, b"".join(rows)


def brute_downscale(raw, width, height, stride, channels, limit):
    """The box filter the helper implements, written the slow, obvious way."""
    if max(width, height) <= limit:
        return width, height, b"".join(raw[y * stride:y * stride + width * channels] for y in range(height))
    scale = max(width, height) / limit
    out_w, out_h = max(1, round(width / scale)), max(1, round(height / scale))
    out = bytearray()
    for oy in range(out_h):
        y0 = oy * height // out_h
        y1 = max(y0 + 1, (oy + 1) * height // out_h)
        for ox in range(out_w):
            x0 = ox * width // out_w
            x1 = max(x0 + 1, (ox + 1) * width // out_w)
            for c in range(channels):
                total = sum(raw[y * stride + x * channels + c] for y in range(y0, y1) for x in range(x0, x1))
                out.append(total // ((y1 - y0) * (x1 - x0)))
    return out_w, out_h, bytes(out)


class CacheTest(unittest.TestCase):
    """Points the helper's cache at a fresh temporary directory."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.saved = (nc.CACHE, nc.IMAGES, nc.INDEX, nc.MAX_BYTES)
        nc.CACHE = os.path.join(self.tmp.name, "cache")
        nc.IMAGES = os.path.join(nc.CACHE, "images")
        nc.INDEX = os.path.join(nc.CACHE, "images.json")
        self.addCleanup(self.restore)

    def restore(self):
        nc.CACHE, nc.IMAGES, nc.INDEX, nc.MAX_BYTES = self.saved

    def files(self):
        return sorted(os.listdir(nc.IMAGES)) if os.path.isdir(nc.IMAGES) else []

    def write(self, name, data=b"\x89PNG\r\n\x1a\n" + b"\0" * 32):
        """A source file outside the cache, as a notifying app would pass."""
        path = os.path.join(self.tmp.name, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        return path


class PixelsTest(unittest.TestCase):
    def test_matches_brute_force_box_filter(self):
        rng = random.Random(7)
        for _ in range(60):
            width, height = rng.randint(1, 340), rng.randint(1, 340)
            channels = rng.choice((3, 4))
            stride = width * channels + rng.choice((0, 1, 8))
            raw = bytes(rng.randrange(256) for _ in range(stride * height))
            got = nc.downscale(raw, width, height, stride, channels, limit=160)
            want = brute_downscale(raw, width, height, stride, channels, 160)
            self.assertEqual((got[1], got[2], got[0]), want, (width, height, channels, stride))

    def test_cover_shrinks_to_thumb_and_keeps_colour(self):
        width = height = 1280
        row = bytes((200, 10, 10, 255)) * (width // 2) + bytes((10, 10, 200, 255)) * (width // 2)
        png = nc.png_from_pixels((width, height, width * 4, True, 8, 4, row * height))
        w, h, channels, pixels = decode_png(png)
        self.assertEqual((w, h, channels), (nc.THUMB, nc.THUMB, 4))
        self.assertEqual(pixels[:4], bytes((200, 10, 10, 255)))
        self.assertEqual(pixels[(w - 1) * 4:w * 4], bytes((10, 10, 200, 255)))

    def test_rejects_malformed_image_data(self):
        # Every bad case carries enough pixel bytes for its stated size, so it
        # is the check it names that rejects it, not the length check.
        good = (2, 2, 8, True, 8, 4, [0] * 16)
        self.assertTrue(nc.png_from_pixels(good))
        for bad in [
            None, (1, 2), ("2", 2, 8, True, 8, 4, [0] * 16),
            (2, 2, 8, True, 16, 4, [0] * 16),   # 16 bits per sample
            (2, 2, 8, True, 8, 2, [0] * 16),    # 2 channels
            (0, 2, 8, True, 8, 4, [0] * 16),    # no width
            (2, 0, 8, True, 8, 4, [0] * 16),    # no height
            (2, 2, 4, True, 8, 4, [0] * 16),    # stride shorter than a row
            (2, 2, 8, True, 8, 4, [0] * 15),    # one byte short
            (2, 2, 8, True, 8, 4, [999] * 16),  # not bytes
            (2, 2, 8, True, 8, 4, 5),           # an int: bytes(5) is too short
            (2, 2, 8, True, 8, 4, 16),          # an int of the right length: bytes(16) is zeros
            (2, 2, 8, True, 8, 4, "x" * 16),    # a string
        ]:
            self.assertEqual(nc.png_from_pixels(bad), b"", bad)

    def test_rejects_more_than_max_pixels(self):
        saved = nc.MAX_PIXELS
        self.addCleanup(setattr, nc, "MAX_PIXELS", saved)
        nc.MAX_PIXELS = 4
        self.assertTrue(nc.png_from_pixels((2, 2, 8, True, 8, 4, [0] * 16)))
        self.assertEqual(nc.png_from_pixels((3, 2, 12, True, 8, 4, [0] * 24)), b"")

    def test_rgb_is_written_as_rgb(self):
        png = nc.png_from_pixels((2, 2, 6, False, 8, 3, [1, 2, 3] * 4))
        self.assertEqual(decode_png(png), (2, 2, 3, bytes([1, 2, 3] * 4)))

    def test_last_row_needs_no_stride_padding(self):
        # GdkPixbuf leaves the last row unpadded: 12-byte stride, 8-byte rows.
        png = nc.png_from_pixels((2, 2, 12, True, 8, 4, list(range(8)) + [0] * 4 + list(range(8, 16))))
        self.assertEqual(decode_png(png), (2, 2, 4, bytes(range(16))))


class CopyFileTest(CacheTest):
    def test_paths_and_file_urls(self):
        path = self.write("img dir/a b\u00e9.png")
        quoted = urllib.parse.quote(path)
        self.assertTrue(nc.copy_file(path))
        self.assertTrue(nc.copy_file("file://" + quoted))
        self.assertTrue(nc.copy_file("file://localhost" + quoted))
        self.assertEqual(nc.copy_file("file://elsewhere" + quoted), "")
        self.assertEqual(nc.copy_file("dialog-information"), "", "a theme icon name")
        self.assertEqual(nc.copy_file(os.path.join(self.tmp.name, "missing.png")), "")

    def test_only_images_are_copied(self):
        self.assertEqual(nc.copy_file(self.write("fake.png", b"not an image at all")), "")
        self.assertEqual(self.files(), [])
        stored = nc.copy_file(self.write("real.png"))
        self.assertTrue(stored.startswith("file://" + nc.IMAGES))
        self.assertTrue(os.path.exists(stored[len("file://"):]))

    def test_webp_is_recognised(self):
        webp = self.write("c.webp", b"RIFF\0\0\0\0WEBPVP8 " + b"\0" * 16)
        self.assertTrue(nc.copy_file(webp).endswith(".webp"))


class ImageForTest(CacheTest):
    """image_for picks the spec's first usable source: image-data,
    image-path, app_icon, then icon_data."""

    def setUp(self):
        super().setUp()
        self.jpg = self.write("a.jpg", b"\xff\xd8\xff" + b"\0" * 32)
        self.png = self.write("b.png")
        self.px = pixels(1)["image-data"]

    def test_precedence(self):
        self.assertTrue(nc.image_for(self.jpg, {"image-data": self.px, "image-path": {"data": self.jpg}}).endswith(".png"))
        self.assertTrue(nc.image_for(self.png, {"image-path": {"data": self.jpg}}).endswith(".jpg"))

    def test_each_source_works_alone(self):
        self.assertTrue(nc.image_for(self.jpg, {}).endswith(".jpg"), "app_icon")
        self.assertTrue(nc.image_for("", {"icon_data": self.px}).endswith(".png"), "icon_data")
        self.assertTrue(nc.image_for("", {"image_data": self.px}).endswith(".png"), "image_data (old name)")


class PruneTest(CacheTest):
    def entry(self, i, size, age):
        url = nc.store(b"\x89PNG\r\n\x1a\n" + bytes([i]) * size, "png")
        return {"id": i, "app": "x", "summary": "", "ts": time.time() - age, "image": url}

    def test_byte_budget_drops_the_oldest(self):
        nc.MAX_BYTES = 2500
        entries = [self.entry(i, 1000, 10 - i) for i in range(3)][::-1]  # newest first
        kept = nc.prune(entries, time.time())
        self.assertEqual([e["id"] for e in kept], [2, 1])
        self.assertEqual(len(self.files()), 2)

    def test_age_limit_missing_files_and_junk(self):
        fresh, stale = self.entry(1, 10, 5), self.entry(2, 10, nc.MAX_AGE + 5)
        gone = {"id": 3, "app": "x", "ts": time.time(), "image": "file:///nowhere/x.png"}
        kept = nc.prune([fresh, stale, gone, {"ts": "x"}, 5, None], time.time())
        self.assertEqual([e["id"] for e in kept], [1])
        self.assertEqual(len(self.files()), 1)

    def test_entries_sharing_an_image_count_its_bytes_once(self):
        nc.MAX_BYTES = 2500  # one 1008-byte file, three entries
        entries = [self.entry(1, 1000, age) for age in range(3)]
        self.assertEqual(len(nc.prune(entries, time.time())), 3)

    def test_byte_budget_keeps_only_the_newest_run(self):
        # An older small image must not outlive a newer one that went over.
        nc.MAX_BYTES = 2500
        entries = [self.entry(1, 1000, 0), self.entry(2, 2000, 1), self.entry(3, 10, 2)]
        self.assertEqual([e["id"] for e in nc.prune(entries, time.time())], [1])

    def test_entry_limit_keeps_the_newest(self):
        self.addCleanup(setattr, nc, "LIMIT", nc.LIMIT)
        nc.LIMIT = 2
        entries = [self.entry(i, 10, i) for i in range(3)]
        self.assertEqual([e["id"] for e in nc.prune(entries, time.time())], [0, 1])

    def test_entry_exactly_max_age_old_is_kept(self):
        entry = self.entry(1, 10, 0)
        self.assertEqual(len(nc.prune([entry], entry["ts"] + nc.MAX_AGE)), 1)

    def test_partly_written_files_survive(self):
        os.makedirs(nc.IMAGES, exist_ok=True)
        open(os.path.join(nc.IMAGES, "x.png.tmp"), "wb").close()
        nc.prune([], time.time())
        self.assertEqual(self.files(), ["x.png.tmp"])

    def test_keep_protects_images_awaiting_a_reply(self):
        waiting = self.entry(9, 10, 0)["image"]
        nc.prune([], time.time(), {os.path.basename(waiting)})
        self.assertEqual(self.files(), [os.path.basename(waiting)])
        nc.prune([], time.time())
        self.assertEqual(self.files(), [])


class IndexTest(CacheTest):
    def test_index_survives_a_restart_and_a_corrupt_one_starts_empty(self):
        nc.save_index([{"id": 1}])
        self.assertEqual(nc.load_index(), [{"id": 1}])
        for junk in ('{"id": 1}', "not json"):
            with open(nc.INDEX, "w") as f:
                f.write(junk)
            self.assertEqual(nc.load_index(), [], junk)


def notify(sender, cookie, app="Chat", hints=None, icon=""):
    data = [app, 0, icon, app + " says hi", "body", [], hints if hints is not None else {}, -1]
    return {"type": "method_call", "member": "Notify", "sender": sender, "cookie": cookie,
            "payload": {"type": "susssasa{sv}i", "data": data}}


def reply(destination, cookie, nid):
    return {"type": "method_return", "destination": destination, "reply_cookie": cookie,
            "payload": {"type": "u", "data": [nid]}}


def pixels(value):
    return {"image-data": {"type": "(iiibiiay)", "data": [2, 2, 8, True, 8, 4, [value] * 16]}}


class HandleTest(CacheTest):
    def run_messages(self, messages):
        pending, entries, out = {}, [], io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            for message in messages:
                entries = nc.handle(message, pending, entries)
        printed = [json.loads(line) for line in out.getvalue().splitlines()]
        return entries, printed

    def test_pairs_call_and_reply_and_prints_the_record(self):
        entries, printed = self.run_messages([notify(":1.5", 10, hints=pixels(1)), reply(":1.5", 10, 42)])
        self.assertEqual([e["id"] for e in entries], [42])
        self.assertEqual(printed[0]["app"], "Chat")
        with open(nc.INDEX) as f:
            self.assertEqual(json.load(f)[0]["id"], 42)

    def test_same_cookie_from_two_senders_keeps_each_image(self):
        entries, _ = self.run_messages([
            notify(":1.5", 10, hints=pixels(1)), notify(":1.6", 10, hints=pixels(2)),
            reply(":1.5", 10, 41), reply(":1.6", 10, 42),
        ])
        stored = lambda value: nc.store(nc.png_from_pixels(pixels(value)["image-data"]["data"]), "png")
        self.assertEqual({e["id"]: e["image"] for e in entries}, {41: stored(1), 42: stored(2)})

    def test_long_summary_is_capped(self):
        call = notify(":1.5", 1, hints=pixels(1))
        call["payload"]["data"][3] = "x" * 1000
        entries, printed = self.run_messages([call, reply(":1.5", 1, 5)])
        self.assertEqual(len(entries[0]["summary"]), 256)
        self.assertEqual(printed[0]["summary"], entries[0]["summary"])

    def test_reply_after_expiry_is_not_recorded(self):
        pending = {}
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            nc.handle(notify(":1.5", 10, hints=pixels(1)), pending, [])
            nc.expire(pending, time.time() + nc.PENDING_TTL + 1)
            self.assertEqual(nc.handle(reply(":1.5", 10, 42), pending, []), [])

    def test_interleaved_replies_keep_both_images(self):
        entries, _ = self.run_messages([
            notify(":1.5", 10, hints=pixels(1)), notify(":1.6", 11, hints=pixels(2)),
            reply(":1.5", 10, 41), reply(":1.6", 11, 42),
        ])
        self.assertEqual(sorted(e["id"] for e in entries), [41, 42])
        for entry in entries:
            self.assertTrue(os.path.exists(entry["image"][len("file://"):]), entry["id"])

    def test_unpaired_and_unexpected_messages_are_ignored(self):
        entries, printed = self.run_messages([
            reply(":1.9", 1, 7),                                 # no call
            notify(":1.5", 10),                                  # no image
            reply(":1.5", 10, 8),
            notify(":1.5", 11, hints=pixels(3)), reply(":1.5", 11, "x"),  # bad id
            {"type": "signal"}, [], "text",
        ])
        self.assertEqual((entries, printed), ([], []))

    def test_malformed_payloads_do_not_raise(self):
        cases = [
            notify(":1.5", 1, hints=5),
            notify(":1.5", 2, hints={"image-data": {"data": ["2", 2, 8, True, 8, 4, [0]]}}),
            notify(":1.5", 3, hints={"image-path": {"data": 12}}),
            {"type": "method_call", "member": "Notify", "payload": {"data": "nope"}},
            {"type": "method_return", "destination": ":1.5", "reply_cookie": 1, "payload": None},
        ]
        entries, printed = self.run_messages(cases)
        self.assertEqual((entries, printed), ([], []))
        self.assertEqual(self.files(), [], "nothing written to the cache")


class ExpireTest(unittest.TestCase):
    def test_drops_only_calls_older_than_the_ttl(self):
        now = 1000.0
        pending = {(":1.5", age): ("app", "s", "img", now - age) for age in (0, nc.PENDING_TTL, nc.PENDING_TTL + 1)}
        nc.expire(pending, now)
        self.assertEqual(sorted(age for _sender, age in pending), [0, nc.PENDING_TTL])


if __name__ == "__main__":
    unittest.main()
