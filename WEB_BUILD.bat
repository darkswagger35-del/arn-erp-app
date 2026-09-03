@echo off
setlocal
cd /d "%~dp0"
title MOTUS Web - Release Build

echo.
echo MOTUS Web release build hazirlaniyor...
echo.

if not exist "%~dp0pubspec.yaml" (
  echo HATA: ZIP icinden calistirmayin. Once Tumunu Ayikla deyin.
  pause
  exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo HATA: Flutter bulunamadi.
  pause
  exit /b 1
)

call flutter pub get
if errorlevel 1 goto :error
call flutter build web --release --dart-define-from-file=config/dev.json
if errorlevel 1 goto :error

echo.
echo TAMAM: Yayina hazir klasor: build\web
pause
exit /b 0

:error
echo.
echo HATA: Web build olusturulamadi.
pause
exit /b 1
