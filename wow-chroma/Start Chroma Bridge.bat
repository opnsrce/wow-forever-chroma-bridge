@echo off
title Chroma Bridge
rem Runs the bridge while you play. Close this window (or press Ctrl+C) to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0chroma-bridge.ps1" %*
echo.
pause
