@echo off
rem Removes the Chroma Bridge addon from every World of Warcraft version on this PC.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
