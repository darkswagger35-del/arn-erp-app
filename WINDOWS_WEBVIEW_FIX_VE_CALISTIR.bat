@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo.
echo ARN ERP - Windows Yandex WebView uyumluluk ve calistirma

echo.
if not exist pubspec.yaml (
  echo HATA: Bu BAT dosyasini pubspec.yaml ile ayni proje klasorune koyun.
  pause
  exit /b 1
)
if exist windows\CMakeLists.txt (
  findstr /C:"_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS" windows\CMakeLists.txt >nul
  if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='windows/CMakeLists.txt'; $s=Get-Content $p -Raw; $needle='project('; $i=$s.IndexOf($needle); if($i -ge 0){$e=$s.IndexOf([Environment]::NewLine,$i); $insert=[Environment]::NewLine+'# webview_windows compatibility with new MSVC'+[Environment]::NewLine+'add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)'+[Environment]::NewLine; $s=$s.Insert($e+$([Environment]::NewLine).Length,$insert); Set-Content $p $s -Encoding UTF8}"
  )
) else (
  echo UYARI: windows\CMakeLists.txt bulunamadi. Mevcut PC projenizde Windows klasoru korunmali.
)
flutter clean
if errorlevel 1 goto :fail
flutter pub get
if errorlevel 1 goto :fail
flutter run -d windows --dart-define-from-file=config/dev.json
exit /b %errorlevel%
:fail
echo.
echo Islem hata ile durdu.
pause
exit /b 1
