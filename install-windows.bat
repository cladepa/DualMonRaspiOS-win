@echo off
rem Install/update Windows side. Double-click to run.
title Second monitor - install (Windows)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1"
echo.
pause
