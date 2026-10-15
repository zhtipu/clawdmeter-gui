#!/usr/bin/env bash
# Builds Clawdmeter.app and Clawdmeter.dmg. Run this on a Mac (or on a GitHub Actions macOS runner).
#   ./build_mac.sh                 normal build in a private virtual environment
#   USE_VENV=0 ./build_mac.sh      use the Python that is already set up (CI does this)
#   SKIP_CHECK=1 ./build_mac.sh    skip the self-check before building
set -euo pipefail
cd "$(dirname "$0")"

if [ "${USE_VENV:-1}" = "1" ]; then
  python3 -m venv .venv-mac
  # shellcheck disable=SC1091
  source .venv-mac/bin/activate
  python -m pip install --upgrade pip
  python -m pip install -r requirements.txt pyinstaller
fi

if [ "${SKIP_CHECK:-0}" != "1" ]; then
  python ci_check.py
fi

rm -rf build dist
python -m PyInstaller --noconfirm --windowed \
  --name Clawdmeter \
  --icon assets/icon.icns \
  --osx-bundle-identifier com.clawdmeter.app \
  --add-data "qml:qml" --add-data "assets:assets" \
  --hidden-import serial.tools.list_ports --hidden-import zeroconf \
  --hidden-import tzdata --collect-data tzdata \
  --exclude-module PySide6.QtWebEngineCore --exclude-module PySide6.QtWebEngineWidgets \
  --exclude-module PySide6.Qt3DCore --exclude-module PySide6.QtCharts \
  --exclude-module PySide6.QtDataVisualization --exclude-module PySide6.QtMultimedia \
  --exclude-module PySide6.QtPdf --exclude-module tkinter \
  main.py

APP="dist/Clawdmeter.app"
PLIST="$APP/Contents/Info.plist"
# a normal Dock app with a menu bar icon; Retina; macOS 11 or newer
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 11.0" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :NSHighResolutionCapable true" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.utilities" "$PLIST" 2>/dev/null || true

# Unsigned for distribution, but Apple Silicon needs at least an ad-hoc signature to run at all
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "ad-hoc signature ok"

hdiutil create -volname Clawdmeter -srcfolder "$APP" -ov -format UDZO dist/Clawdmeter.dmg
ls -lh dist
echo "Done: dist/Clawdmeter.dmg"
