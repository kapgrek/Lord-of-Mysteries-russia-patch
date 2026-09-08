@echo off
chcp 65001 >nul
title Lord of the Mysteries - Русский патч (Установка)
echo ============================================================
echo   Lord of the Mysteries - Установка русского патча v2.6-RU
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Lord-of-Mysteries-Russian-Patch.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Возникли ошибки при установке. Нажмите любую клавишу для выхода...
    pause >nul
)
