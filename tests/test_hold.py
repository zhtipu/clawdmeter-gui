"""One sender per TV: when this computer holds back for a phone, and when it takes a TV over."""
import json
import os
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import engine

TV = "192.168.0.31"


def reset():
    with engine.state.lock:
        engine.state.clients.clear()
        engine.state.takeover.clear()
        engine.state.push_results.clear()


def phone(key="1.2.3.4", tvs=(TV,), report=None, age=0.0, since_age=0.0):
    engine.register_client(key, "Pixel", "wifi", set(tvs), report or {})
    c = engine.state.clients[key]
    c["last"] = time.time() - age
    c["since"] = {h: time.time() - since_age for h in tvs}
    return c


class Owners(unittest.TestCase):
    def setUp(self):
        reset()

    def test_phone_that_reports_success_owns_the_tv(self):
        phone(report={TV: "ok"})
        self.assertEqual(engine.state.phone_owners(), {TV: "1.2.3.4"})

    def test_new_claim_is_honoured_for_a_short_grace(self):
        phone(report={}, since_age=20)
        self.assertIn(TV, engine.state.phone_owners())

    def test_claim_with_no_result_stops_holding_the_computer_back(self):
        # e.g. the phone's relay is switched off, so it never sends anything
        phone(report={}, since_age=120)
        self.assertEqual(engine.state.phone_owners(), {})

    def test_failed_phone_is_replaced_and_told_to_skip(self):
        phone(report={TV: "fail"})
        self.assertTrue(engine.state.taken_over(TV))
        self.assertEqual(engine.state.phone_owners(), {})
        self.assertEqual(engine.skip_for("1.2.3.4"), [TV])

    def test_silent_phone_is_not_live(self):
        phone(report={TV: "ok"}, age=200)
        self.assertEqual(engine.state.phone_owners(), {})

    def test_slow_phone_stays_live_between_calls(self):
        c = phone(report={TV: "ok"})
        c["gap"] = 300                         # it calls every five minutes
        c["last"] = time.time() - 400
        self.assertIn(TV, engine.state.phone_owners())

    def test_first_phone_keeps_a_tv_both_claim(self):
        a = phone("a", report={TV: "ok"})
        a["first"] -= 100
        phone("b", report={TV: "ok"})
        self.assertEqual(engine.state.phone_owners()[TV], "a")
        self.assertEqual(engine.skip_for("b"), [TV])
        self.assertEqual(engine.skip_for("a"), [])

    def test_takeover_expires(self):
        phone(report={TV: "fail"})
        engine.state.takeover[TV] = time.time() - 1
        self.assertFalse(engine.state.taken_over(TV))


class Push(unittest.TestCase):
    """The computer's own push loop against a pretend TV."""

    def run_loop(self, reply, status_reply, url_host="127.0.0.1", seconds=1.5):
        hits = {"usage": 0, "status": 0}

        class H(BaseHTTPRequestHandler):
            def do_POST(s):
                s.rfile.read(int(s.headers.get("Content-Length", 0)))
                hits["usage"] += 1
                s.send_response(200); s.send_header("Content-Length", str(len(reply))); s.end_headers(); s.wfile.write(reply)

            def do_GET(s):
                hits["status"] += 1
                if status_reply is None:
                    s.send_response(404); s.end_headers(); return
                s.send_response(200); s.send_header("Content-Length", str(len(status_reply))); s.end_headers(); s.wfile.write(status_reply)

            def log_message(s, *a):
                pass

        srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        url = f"http://{url_host}:{srv.server_port}/api/usage"
        engine.state.set_payload({"ok": True, "s": 10, "w": 20, "sr": 5, "wr": 6, "st": "allowed"})
        stop = threading.Event()
        threading.Thread(target=engine.push_loop, args=(stop, lambda: [url], 0.3), daemon=True).start()
        time.sleep(seconds)
        stop.set()
        srv.shutdown()
        srv.server_close()
        return engine.state.push_results.get(url), hits

    def setUp(self):
        reset()

    def test_real_tv_reply_is_success(self):
        res, _ = self.run_loop(b'{"ok":true}', None)
        self.assertTrue(res[0])

    def test_html_page_is_not_a_tv(self):
        res, _ = self.run_loop(b"<html>router</html>", None)
        self.assertFalse(res[0])
        self.assertEqual(res[2], "That address is not the SmallTV")

    def test_older_firmware_with_a_different_reply_still_counts(self):
        res, hits = self.run_loop(b"ok", json.dumps({"fw": "smalltv", "version": "1.0"}).encode())
        self.assertTrue(res[0])
        self.assertGreater(hits["status"], 0)

    def test_computer_holds_back_while_a_phone_sends(self):
        engine.register_client("p", "Pixel", "wifi", {"127.0.0.1"}, {"127.0.0.1": "ok"})
        res, hits = self.run_loop(b'{"ok":true}', None)
        self.assertEqual(hits["usage"], 0)
        self.assertEqual(res[2], "phone")


if __name__ == "__main__":
    result = unittest.main(exit=False).result
    failures = len(result.failures) + len(result.errors)
    print("FAILURES:", failures)
    sys.exit(1 if failures else 0)
