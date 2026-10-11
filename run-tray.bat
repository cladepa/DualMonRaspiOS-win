@echo off
rem Starts the tray icon (hidden). Exit: icon menu -> Exit.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0windows\second-monitor-run.ps1"
