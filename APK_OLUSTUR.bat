@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo MOTUS ANDROID APK OLUSTURUCU
echo ============================================

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

echo.
echo [1/4] Flutter kontrol...
call flutter --version
if errorlevel 1 goto :fail

echo.
echo [2/4] Paketler aliniyor...
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo [3/4] Temiz build...
call flutter clean
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo [4/4] Release APK olusturuluyor...
call flutter build apk --release --dart-define-from-file=config/dev.json
if errorlevel 1 goto :fail

if not exist build\app\outputs\flutter-apk\app-release.apk goto :fail

copy /Y build\app\outputs\flutter-apk\app-release.apk MOTUS_ANDROID.apk >nul

echo.
echo ============================================
echo BASARILI!
echo APK:
echo %CD%\MOTUS_ANDROID.apk
echo ============================================
explorer /select,"%CD%\MOTUS_ANDROID.apk"
pause
exit /b 0

:fail
echo.
echo ============================================
echo APK OLUSTURMA BASARISIZ.
echo Bu pencerenin ekran goruntusunu veya logu gonder.
echo ============================================
pause
exit /b 1
