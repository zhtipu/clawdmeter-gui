import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import usage_cli as u

fails = 0


def check(name, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else " " + str(extra)))
    fails += 0 if cond else 1


# Real output of `claude -p /usage`, captured from Claude Code 2.1.x
REAL = """You are currently using your subscription to power your Claude Code usage

Current session: 9% used · resets Oct 15, 11:29pm (Asia/Dhaka)
Current week (all models): 46% used · resets Oct 18, 4:59pm (Asia/Dhaka)

What's contributing to your limits usage?
Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.

Last 24h · 11 requests · 3 sessions
  89% of your usage was at >150k context
"""

# 2026-10-15 05:00 in Dhaka (UTC+6) is 2026-10-14 23:00 UTC
NOW = dt.datetime(2026, 10, 14, 23, 0, tzinfo=dt.timezone.utc)

p = u.parse_usage(REAL, NOW)
check("real output is parsed", p is not None and p["s"] == 9 and p["w"] == 46, p)
check("session reset minutes", p and p["sr"] == 18 * 60 + 29, p and p["sr"])           # 05:00 to 23:29 = 18h29m
check("week reset minutes", p and p["wr"] == 3 * 1440 + 11 * 60 + 59, p and p["wr"])  # Oct 15 05:00 to Oct 18 16:59
check("status allowed below 90", p and p["st"] == "allowed")
check("payload says ok", p and p["ok"] is True)

check("90 percent is a warning", u.parse_usage("Current session: 91% used", NOW)["st"] == "warning")
check("100 percent is rejected", u.parse_usage("Current session: 100% used", NOW)["st"] == "rejected")

only_session = u.parse_usage("Current session: 0% used\n", NOW)
check("a line with no reset time still parses", only_session and only_session["sr"] == 0 and only_session["w"] == 0, only_session)

several = u.parse_usage(
    "Current session: 5% used · resets 11pm\n"
    "Current week (Sonnet only): 80% used · resets Oct 18, 4:59pm (Asia/Dhaka)\n"
    "Current week (all models): 12% used · resets Oct 18, 4:59pm (Asia/Dhaka)\n", NOW)
check("the all-models week line wins", several and several["w"] == 12, several)

check("ansi colour codes are ignored", u.parse_usage("\x1b[1mCurrent session: 7% used\x1b[0m", NOW)["s"] == 7)
check("decimals round", u.parse_usage("Current session: 9.6% used", NOW)["s"] == 10)

# times without a date roll to the next day, dates in the past roll to next year
check("time only, later today", u.minutes_until("5:30am (Asia/Dhaka)", NOW) == 30, u.minutes_until("5:30am (Asia/Dhaka)", NOW))
check("time only, already passed rolls to tomorrow", u.minutes_until("4:30am (Asia/Dhaka)", NOW) == 23 * 60 + 30)
check("hour without minutes", u.minutes_until("6am (Asia/Dhaka)", NOW) == 60)
check("noon and midnight", u.minutes_until("12pm (Asia/Dhaka)", NOW) == 7 * 60 and u.minutes_until("12am (Asia/Dhaka)", NOW) == 19 * 60)
check("date in the past rolls to next year", u.minutes_until("Jan 2, 1:00am (Asia/Dhaka)", NOW) > 60 * 24 * 60)
check("garbage gives zero", u.minutes_until("soon", NOW) == 0)

# classification of what the program says when it cannot give usage
check("ok", u.classify(REAL, 0).kind == "ok")
check("signed out", u.classify("Not logged in · Please run /login", 1).kind == "signed_out")
check("api key login", u.classify("You are currently using API key billing. Usage limits are for subscriptions.", 0).kind == "no_limits")
COST = """Total cost:            $0.0000
Total duration (API):  0s
Total duration (wall): 0s
Total code changes:    0 lines added, 0 lines removed
Usage:                 0 input, 0 output, 0 cache read, 0 cache write
"""
r = u.classify(COST, 0)
check("signed-out cost summary is explained", r.kind == "no_limits" and "Sign in" in r.message, r)
check("crash", u.classify("", 3).kind == "fail")
check("odd output", u.classify("something else entirely", 0).kind == "fail")

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
