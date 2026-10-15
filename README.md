# Clawdmeter

Shows your Claude Code usage (the 5 hour and 7 day limits) on your computer and on a SmallTV, with alerts when a limit
gets close. Also includes the SmallTV's full settings. Windows and macOS.

## Where the usage numbers come from

The app runs the official Claude Code program with its usage command (`claude -p /usage`) and reads the two limit lines it
prints. That is all.

- It never opens, copies or stores your Claude login or any token.
- It does not talk to Anthropic itself. Signing in always happens inside Claude Code.
- Each reading starts Claude Code for a few seconds, so readings are minutes apart (default 5 minutes, never faster than 2).

`tests/test_compliance.py` fails the build if code that handles tokens, credentials or Anthropic's API is ever added.

## Build

- Windows: `build_windows.bat`
- macOS: see `MAC.md`

Requires Claude Code to be installed and signed in. Not affiliated with Anthropic.
