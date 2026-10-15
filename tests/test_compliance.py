"""Guard: this app must never handle a Claude login or call Anthropic itself. Usage comes only from the official
`claude -p /usage` (usage_cli.py). If this test fails, someone added code that reads credentials or talks to the API."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORBIDDEN = [
    "api.anthropic.com", "platform.claude.com", "claude.ai/", "oauth/token", "oauth/usage", "oauth/authorize",
    "credentials.json", ".credentials", "Bearer ", "claude-code/", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY",
    "refresh_token", "access_token", "accessToken", "refreshToken", "keyring", "keychain", "Keychain",
]
EXTENSIONS = (".py", ".qml", ".js", ".sh", ".yml", ".bat", ".txt")
SKIP_DIRS = {"tests", "build", "dist", ".git", ".venv-mac", "__pycache__", "shots", "themes"}
SKIP_FILES = {"LUCIDE-LICENSE.txt", "LICENSE-clawdmeter-daemon"}

hits = []
for dirpath, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    for f in files:
        if not f.endswith(EXTENSIONS) or f in SKIP_FILES:
            continue
        path = os.path.join(dirpath, f)
        text = open(path, encoding="utf-8", errors="replace").read()
        for bad in FORBIDDEN:
            if bad in text:
                hits.append((os.path.relpath(path, ROOT), bad))

for path, bad in hits:
    print("FAIL", path, "contains", repr(bad))
if not hits:
    print("PASS no token, credential or Anthropic API code in the app")
print("FAILURES:", len(hits))
sys.exit(1 if hits else 0)
