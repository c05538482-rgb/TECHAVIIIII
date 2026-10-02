@echo off
setlocal
title TechAvı - Hizli Arama Kurulumu

echo ========================================
echo   TECHAVI - HIZLI ARAMA KURULUMU
echo ========================================
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo [HATA] PowerShell bulunamadi.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kurulum.ps1"
if errorlevel 1 (
  echo.
  echo [HATA] Kurulum basarisiz.
  pause
  exit /b 1
)

echo.
echo [TAMAM] Guncel proje TECHAVIII_HIZLI_ARAMA klasorune olusturuldu.
pause
