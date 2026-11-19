@echo off
rem Stops a Chroma Bridge running in the background. It starts again at your next Windows sign-in if automatic start is on.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0chroma-bridge.ps1" -Stop
rem Leave the message on screen for a moment before the window closes.
timeout /t 3 >nul
