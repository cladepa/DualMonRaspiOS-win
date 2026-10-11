@echo off
rem Windows side diagnostics. Double-click to run.
title Second monitor - doctor (Windows)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\sm-doctor.ps1"
echo.
pause
