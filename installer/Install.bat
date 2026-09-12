@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Lord of the Mysteries - Russian Patch Installer

if exist "Lord-of-Mysteries-Russian-Patch.exe" (
    start "" "Lord-of-Mysteries-Russian-Patch.exe"
    exit /b 0
)
if exist "..\Lord-of-Mysteries-Russian-Patch.exe" (
    start "" "..\Lord-of-Mysteries-Russian-Patch.exe"
    exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Lord-of-Mysteries-Russian-Patch.ps1"