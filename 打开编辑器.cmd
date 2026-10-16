@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Start-Godot.ps1" -Mode Editor
if errorlevel 1 pause
