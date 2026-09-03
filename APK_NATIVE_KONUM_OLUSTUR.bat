@echo off
setlocal
cd /d "%~dp0"

echo ================================================
echo MOTUS V70 - NATIVE ARKA PLAN KONUM APK
echo ================================================

where flutter >nul 2>nul
if errorlevel 1 (
  if exist C:\flutter\bin\flutter.bat (
    set "PATH=C:\flutter\bin;%PATH%"
  ) else (
    echo HATA: Flutter bulunamadi.
    pause
    exit /b 1
  )
)

echo [1/4] Temizleniyor...
call flutter clean
if errorlevel 1 goto :fail

echo [2/4] Paketler...
call flutter pub get
if errorlevel 1 goto :fail

echo [3/4] Android release APK...
call flutter build apk --release --dart-define-from-file=config/dev.json
if errorlevel 1 goto :fail

if not exist build\app\outputs\flutter-apk\app-release.apk goto :fail

echo [4/4] APK kopyalaniyor...
copy /Y build\app\outputs\flutter-apk\app-release.apk MOTUS_ANDROID_NATIVE_KONUM.apk >nul

echo.
echo ================================================
echo BASARILI
echo %CD%\MOTUS_ANDROID_NATIVE_KONUM.apk
echo ================================================
explorer /select,"%CD%\MOTUS_ANDROID_NATIVE_KONUM.apk"
pause
exit /b 0

:fail
echo.
echo APK BUILD BASARISIZ.
echo Son ekrani veya logu ChatGPT'ye gonder.
pause
exit /b 1
