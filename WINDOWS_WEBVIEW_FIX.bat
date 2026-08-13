@echo off
setlocal
cd /d "%~dp0"
if not exist "windows\CMakeLists.txt" (
  echo HATA: windows\CMakeLists.txt bulunamadi.
  echo Bu dosyayi Flutter projesinin ana klasorune kopyalayip tekrar calistir.
  pause
  exit /b 1
)
copy /Y "windows\CMakeLists.txt" "windows\CMakeLists.txt.bak" >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='windows/CMakeLists.txt'; $c=Get-Content $p -Raw; $d='add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)'; if($c -notmatch [regex]::Escape($d)){ $m=[regex]::Match($c,'(?m)^project\([^\r\n]+\)\s*$'); if($m.Success){ $c=$c.Insert($m.Index+$m.Length,[Environment]::NewLine+[Environment]::NewLine+$d); Set-Content -Path $p -Value $c -Encoding UTF8 } else { Write-Error 'project(...) satiri bulunamadi'; exit 2 } }"
if errorlevel 1 (
  echo HATA: CMakeLists.txt duzenlenemedi.
  pause
  exit /b 1
)
echo.
echo FIX uygulandi. Yedek: windows\CMakeLists.txt.bak
echo.
echo Simdi Flutter temizleniyor...
call flutter clean
if errorlevel 1 goto fluttererr
call flutter pub get
if errorlevel 1 goto fluttererr
echo.
echo Program baslatiliyor...
call flutter run -d windows --dart-define-from-file=config/dev.json
exit /b %errorlevel%
:fluttererr
echo Flutter komutunda hata olustu.
pause
exit /b 1
