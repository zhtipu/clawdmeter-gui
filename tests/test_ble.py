"""The Bluetooth wire format. The phone app (BleCodec in Kotlin) must read and write exactly the same bytes."""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import ble


class UsageBytes(unittest.TestCase):
    def test_known_bytes(self):
        # also asserted in the phone app's tests, so a change on one side breaks the other
        b = ble.encode_usage({"ok": True, "s": 52, "w": 54, "sr": 160, "wr": 4000, "st": "allowed"})
        self.assertEqual(list(b), [1, 52, 54, 160, 0, 0xA0, 0x0F, 1])

    def test_round_trip(self):
        p = {"ok": True, "s": 91, "w": 12, "sr": 65535, "wr": 10080, "st": "rejected"}
        self.assertEqual(ble.decode_usage(ble.encode_usage(p)), p)

    def test_values_are_clamped(self):
        d = ble.decode_usage(ble.encode_usage({"ok": True, "s": 400, "w": -5, "sr": 99999, "wr": 3}))
        self.assertEqual((d["s"], d["w"], d["sr"], d["wr"]), (255, 0, 65535, 3))

    def test_not_ok_and_garbage(self):
        self.assertFalse(ble.decode_usage(ble.encode_usage({"ok": False}))["ok"])
        self.assertEqual(ble.decode_usage(b"\x09\x01"), {"ok": False})
        self.assertEqual(ble.decode_usage(bytes([2, 0, 0, 0, 0, 0, 0, 1])), {"ok": False})     # unknown version

    def test_fits_one_packet(self):
        self.assertEqual(len(ble.encode_usage({"ok": True})), 8)


class Control(unittest.TestCase):
    def test_skip_list_round_trips(self):
        raw = ble.encode_ctrl("Tipu", ["192.168.0.31"])
        self.assertEqual(json.loads(raw), {"pc": "Tipu", "skip": ["192.168.0.31"]})

    def test_stays_inside_one_packet(self):
        raw = ble.encode_ctrl("A" * 80, [f"192.168.0.{i}" for i in range(60)])
        self.assertLessEqual(len(raw), 180)


class PhoneSide(unittest.TestCase):
    def test_status(self):
        name, tvs, report = ble.parse_status(json.dumps({"name": "Pixel 8", "tvs": ["192.168.0.31", " TV.local "], "ok": {"192.168.0.31": "ok", "tv.local": "fail", "x": "weird"}}).encode())
        self.assertEqual(name, "Pixel 8")
        self.assertEqual(tvs, {"192.168.0.31", "tv.local"})
        self.assertEqual(report, {"192.168.0.31": "ok", "tv.local": "fail"})

    def test_bad_status_is_harmless(self):
        self.assertEqual(ble.parse_status(b"not json"), ("", set(), {}))

    def test_advert_carries_id_and_name(self):
        self.assertEqual(ble.parse_advert({0xFFFF: bytes([0xDE, 0xAD, 0xBE, 0xEF]) + b"Pixel 8"}), ("deadbeef", "Pixel 8"))
        self.assertIsNone(ble.parse_advert({0x004C: b"\x01\x02\x03\x04\x05"}))
        self.assertIsNone(ble.parse_advert({0xFFFF: b"\x01"}))


class FakeLink(unittest.TestCase):
    """The connect, write, read loop against a pretend phone, so only the real radio is left untested."""

    def test_loop_writes_numbers_and_registers_the_phone(self):
        import asyncio
        import time
        import types
        import bleak

        writes, regs = [], []

        class Client:
            def __init__(self, dev, timeout=0):
                self.n = 0

            async def __aenter__(self):
                return self

            async def __aexit__(self, *a):
                return False

            @property
            def is_connected(self):
                self.n += 1
                return self.n < 50

            async def write_gatt_char(self, uuid, data, response=True):
                writes.append((uuid, bytes(data)))

            async def read_gatt_char(self, uuid):
                return json.dumps({"name": "Pixel 8", "tvs": ["192.168.0.31:80"], "ok": {"192.168.0.31:80": "fail"}}).encode()

        async def find(match, timeout=0):
            adv = types.SimpleNamespace(manufacturer_data={0xFFFF: bytes.fromhex("deadbeef") + b"Pixel 8"})
            dev = object()
            return dev if match(dev, adv) else None

        saved = (bleak.BleakClient, bleak.BleakScanner.find_device_by_filter)
        bleak.BleakClient = Client
        bleak.BleakScanner.find_device_by_filter = staticmethod(find)
        try:
            link = ble.BleLink(lambda: {"ok": True, "s": 52, "w": 54, "sr": 160, "wr": 4000},
                               lambda *a: regs.append(a), lambda key: ["192.168.0.31"], lambda m: None, "Tipu", interval=0.02)
            link.sync([{"id": "deadbeef", "name": "Pixel"}])
            deadline = time.time() + 5
            while len(writes) < 4 and time.time() < deadline:
                time.sleep(0.05)
            status = dict(link.status["deadbeef"])
            link.sync([])                                    # removing the phone stops the loop
            time.sleep(0.1)
        finally:
            bleak.BleakClient, bleak.BleakScanner.find_device_by_filter = saved

        self.assertEqual(writes[0], (ble.USAGE, bytes([1, 52, 54, 160, 0, 0xA0, 0x0F, 1])))
        self.assertEqual(writes[1][0], ble.CTRL)
        self.assertEqual(json.loads(writes[1][1]), {"pc": "Tipu", "skip": ["192.168.0.31"]})
        self.assertEqual(regs[0], ("ble:deadbeef", "Pixel 8", "bluetooth", {"192.168.0.31"}, {"192.168.0.31": "fail"}))
        self.assertEqual(status["state"], "connected")
        self.assertNotIn("deadbeef", link.status)


if __name__ == "__main__":
    result = unittest.main(exit=False).result
    failures = len(result.failures) + len(result.errors)
    print("FAILURES:", failures)          # the line ci_check.py looks for, like the other test scripts
    sys.exit(1 if failures else 0)
