"""Everything that differs between Windows, macOS and Linux lives here, so the rest of the app stays the same.
Nothing here handles a Claude login or token."""
import os
import plistlib
import shutil
import subprocess
import sys

IS_WIN = sys.platform == "win32"
IS_MAC = sys.platform == "darwin"
APP_NAME = "Clawdmeter"

# Windows startup entries (registry value names ignore case, so the two must differ)
WIN_RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
WIN_RUN_NAME = "ClawdmeterApp"
WIN_OLD_RUN_NAME = "clawdmeter"            # the command-line daemon's entry

# macOS login item
MAC_LABEL = "com.clawdmeter.app"
MAC_OLD_LABEL = "com.giovi321.clawdmeter"  # the command-line daemon's LaunchAgent



def data_dir():
    """Where the app keeps files it creates (patched themes and the like)."""
    if IS_WIN:
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        path = os.path.join(base, APP_NAME)
    elif IS_MAC:
        path = os.path.join(os.path.expanduser("~"), "Library", "Application Support", APP_NAME)
    else:
        path = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share"), APP_NAME.lower())
    os.makedirs(path, exist_ok=True)
    return path


# ---- Claude Code sign-in ---------------------------------------------------

def find_claude():
    """The Claude Code CLI is often in a folder that a GUI app's PATH does not include."""
    home = os.path.expanduser("~")
    if IS_WIN:
        extra = [os.path.join(home, ".local", "bin"), os.path.join(os.environ.get("APPDATA", ""), "npm"),
                 os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "claude"), os.path.join(home, ".claude", "local")]
    else:
        extra = [os.path.join(home, ".local", "bin"), os.path.join(home, ".claude", "local"), "/opt/homebrew/bin", "/usr/local/bin",
                 os.path.join(home, ".npm-global", "bin"), os.path.join(home, ".volta", "bin"), "/usr/bin"]
    path = os.pathsep.join(extra + [os.environ.get("PATH", "")])
    found = shutil.which("claude", path=path)
    return found or ""


def _applescript_quote(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def open_sign_in(exe):
    """Open a terminal window running `claude auth login`. Raises OSError if it cannot."""
    if IS_WIN:
        subprocess.Popen(f'cmd.exe /k ""{exe}" auth login"', creationflags=0x00000010)    # CREATE_NEW_CONSOLE
    elif IS_MAC:
        cmd = _applescript_quote(f'"{exe}" auth login')
        subprocess.Popen(["osascript",
                          "-e", 'tell application "Terminal"',
                          "-e", "activate",
                          "-e", f'do script "{cmd}"',
                          "-e", "end tell"])
    else:
        for term in (["x-terminal-emulator", "-e"], ["gnome-terminal", "--"], ["konsole", "-e"], ["xterm", "-e"]):
            if shutil.which(term[0]):
                subprocess.Popen(term + [exe, "auth", "login"])
                return
        raise OSError("no terminal program found")


# ---- sound ------------------------------------------------------------------

def beep_critical():
    try:
        if IS_WIN:
            import winsound
            winsound.MessageBeep(winsound.MB_ICONHAND)
        elif IS_MAC:
            subprocess.Popen(["afplay", "/System/Library/Sounds/Basso.aiff"])
    except Exception:
        pass


# ---- start at login ----------------------------------------------------------

def _mac_app_bundle():
    """/Applications/Clawdmeter.app when running from a packaged app, else None."""
    exe = os.path.abspath(sys.executable)
    marker = ".app" + os.sep + "Contents" + os.sep
    if getattr(sys, "frozen", False) and marker in exe:
        return exe[:exe.index(marker) + 4]
    return None


def app_command():
    """The command that starts this app hidden in the tray, as an argument list."""
    if getattr(sys, "frozen", False):
        if IS_MAC and _mac_app_bundle():
            return ["/usr/bin/open", "-g", "-a", _mac_app_bundle(), "--args", "--tray"]
        return [sys.executable, "--tray"]
    exe = sys.executable
    if IS_WIN:
        w = os.path.join(os.path.dirname(exe), "pythonw.exe")
        exe = w if os.path.isfile(w) else exe
    return [exe, os.path.abspath(sys.argv[0]), "--tray"]


def _mac_plist(label):
    return os.path.join(os.path.expanduser("~"), "Library", "LaunchAgents", label + ".plist")


def autostart_enabled():
    if IS_WIN:
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, WIN_RUN_KEY) as k:
                winreg.QueryValueEx(k, WIN_RUN_NAME)
                return True
        except OSError:
            return False
    if IS_MAC:
        return os.path.isfile(_mac_plist(MAC_LABEL))
    return False


def autostart_set(on):
    """True on success, otherwise a short reason string."""
    if IS_WIN:
        import winreg
        try:
            with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, WIN_RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
                if on:
                    winreg.SetValueEx(k, WIN_RUN_NAME, 0, winreg.REG_SZ, subprocess.list2cmdline(app_command()))
                    try:        # the command-line daemon would push a second copy of the same data
                        winreg.DeleteValue(k, WIN_OLD_RUN_NAME)
                    except OSError:
                        pass
                else:
                    try:
                        winreg.DeleteValue(k, WIN_RUN_NAME)
                    except OSError:
                        pass
            return True
        except OSError as e:
            return str(e)
    if IS_MAC:
        try:
            path = _mac_plist(MAC_LABEL)
            if on:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    plistlib.dump({"Label": MAC_LABEL, "ProgramArguments": app_command(), "RunAtLoad": True,
                                   "ProcessType": "Interactive"}, f)
                old = _mac_plist(MAC_OLD_LABEL)
                if os.path.isfile(old):
                    subprocess.run(["launchctl", "unload", old], capture_output=True)
                    os.remove(old)
            elif os.path.isfile(path):
                os.remove(path)
            return True
        except OSError as e:
            return str(e)
    return "Start at login is not supported here"
