# Clawdmeter on macOS

## Getting the app

A Mac app cannot be built on Windows, so it is built by GitHub Actions on a Mac runner.

1. Put this folder in a GitHub repository and push it to the `main` branch. The workflow in `.github/workflows/build-mac.yml` starts by itself. You can also start it from the repository's **Actions** tab with **Run workflow**.
2. When the run finishes, open it and download the artifact **Clawdmeter-macOS-arm64**. It holds `Clawdmeter.dmg` and a zipped copy of the app. Only Apple Silicon Macs (M1 and newer) are built; Intel Macs are not supported.
3. The **screenshots** artifact shows each page as it rendered on the Mac runner.

To build by hand on a Mac instead, run `./build_mac.sh`. It makes `dist/Clawdmeter.dmg`.

## Opening an unsigned app

The app is not signed with an Apple Developer ID, so macOS blocks it the first time.

- Drag Clawdmeter to Applications, then **right-click it and choose Open**, then click Open again.
- If macOS says the app is damaged, run this once in Terminal: `xattr -dr com.apple.quarantine /Applications/Clawdmeter.app`

## What changes on a Mac

| Thing | On Windows | On macOS |
|---|---|---|
| Start at login | Registry | A login item at `~/Library/LaunchAgents/com.clawdmeter.app.plist` |
| Saved token | The user environment | The Keychain, under the name Clawdmeter |
| Sign in | Opens a command window | Opens Terminal and runs `claude auth login` |
| Claude Code sign-in | A credentials file | Read from the Keychain, as Claude Code stores it |
| Critical alert sound | Windows alert sound | The Basso system sound |
| Where the app sits | Tray icon | Dock icon and a menu bar icon. Closing the window keeps it running; Cmd+Q quits |
| Fonts | Segoe UI | The system font |
| Icons | Lucide | Lucide |

The first time the app reads Claude Code's Keychain entry, macOS asks for permission. Choose **Always Allow**.

Settings and alert choices are stored in `~/.clawdmeter-gui.json` and `~/.clawdmeter-daemon.json`. The log is `~/.clawdmeter-daemon.log`.

## Not tested yet

Nothing here has run on a real Mac. The CI run checks the logic, the login item file, the Keychain, the theme patch and that every page renders, but it cannot click, hear a sound, or show a Notification Centre banner. Try those on a Mac and report anything odd.
