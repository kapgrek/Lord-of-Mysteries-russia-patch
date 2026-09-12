@echo off
chcp 65001 >nul
title Lord of the Mysteries — Диагностика, Сбор логов и Дамп текстур

cd /d "%~dp0"

if not exist "Lord-of-Mysteries-Diagnostic-Tool.exe" (
    echo Компиляция утилиты диагностики...
    powershell -ExecutionPolicy Bypass -File "tools\build_diagnostic_tool.ps1"
)

if exist "Lord-of-Mysteries-Diagnostic-Tool.exe" (
    start "" "Lord-of-Mysteries-Diagnostic-Tool.exe"
) else (
    echo ОШИБКА: Не удалось скомпилировать или запустить Lord-of-Mysteries-Diagnostic-Tool.exe
    pause
)
