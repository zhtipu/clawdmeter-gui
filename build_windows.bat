@echo off
rem Builds dist\Clawdmeter App.exe. Run from this folder with the Python that has the requirements installed.
rem   python -m pip install -r requirements.txt pyinstaller
setlocal
cd /d "%~dp0"
python -m PyInstaller --noconfirm --onefile --windowed --name "Clawdmeter App" --icon assets\icon.ico ^
  --add-data "qml;qml" --add-data "assets;assets" ^
  --hidden-import serial.tools.list_ports --hidden-import zeroconf --hidden-import tzdata --collect-data tzdata ^
  --exclude-module PySide6.QtWebEngineCore --exclude-module PySide6.QtWebEngineWidgets ^
  --exclude-module PySide6.Qt3DCore --exclude-module PySide6.QtCharts ^
  --exclude-module PySide6.QtDataVisualization --exclude-module PySide6.QtMultimedia ^
  --exclude-module PySide6.QtPdf --exclude-module tkinter main.py
endlocal
