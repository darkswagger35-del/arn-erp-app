@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "LOG=%~dp0WEB_YAYINLA_LOG.txt"
>"%LOG%" echo MOTUS WEB YAYINLAMA LOGU
>>"%LOG%" echo Tarih: %date% %time%
>>"%LOG%" echo Klasor: %CD%
>>"%LOG%" echo.

cls
echo =============================================
echo   MOTUS WEB - VERCEL'E YAYINLA V59
echo =============================================
echo.
echo Bu islem MOTUS Web'i internete yayinlar.
echo Ilk kullanimda Vercel girisi icin tarayici acilabilir.
echo Bu pencereyi islem bitene kadar kapatmayin.
echo.

where flutter >nul 2>&1
if errorlevel 1 (
  echo HATA: Flutter bulunamadi.
  >>"%LOG%" echo HATA: Flutter bulunamadi.
  goto :fail
)

if not exist "config\dev.json" (
  echo HATA: config\dev.json bulunamadi.
  >>"%LOG%" echo HATA: config\dev.json bulunamadi.
  goto :fail
)

where npx >nul 2>&1
if errorlevel 1 (
  echo HATA: Node.js / npx bulunamadi.
  echo Vercel'e yayinlamak icin Node.js kurulmasi gerekiyor.
  echo Node.js kurulduktan sonra bu dosyayi tekrar calistirin.
  >>"%LOG%" echo HATA: Node.js / npx bulunamadi.
  goto :fail
)

echo [1/4] Flutter paketleri kontrol ediliyor...
>>"%LOG%" echo ===== FLUTTER PUB GET =====
call flutter pub get >>"%LOG%" 2>&1
if errorlevel 1 (
  echo HATA: flutter pub get basarisiz.
  goto :fail
)

echo [2/4] Web surumu hazirlaniyor...
>>"%LOG%" echo.
>>"%LOG%" echo ===== FLUTTER BUILD WEB =====
call flutter build web --release --dart-define-from-file=config/dev.json >>"%LOG%" 2>&1
if errorlevel 1 (
  echo HATA: Web build olusturulamadi.
  goto :fail
)

if not exist "build\web\index.html" (
  echo HATA: build\web\index.html olusmadi.
  >>"%LOG%" echo HATA: build\web\index.html olusmadi.
  goto :fail
)

if not exist "vercel\api\yandex-geocode.js" (
  echo HATA: vercel\api\yandex-geocode.js bulunamadi.
  >>"%LOG%" echo HATA: Yandex proxy dosyasi bulunamadi.
  goto :fail
)
if not exist "build\web\api" mkdir "build\web\api"
copy /Y "vercel\api\yandex-geocode.js" "build\web\api\yandex-geocode.js" >nul
if errorlevel 1 (
  echo HATA: Yandex proxy dosyasi yayin klasorune kopyalanamadi.
  >>"%LOG%" echo HATA: Yandex proxy kopyalama basarisiz.
  goto :fail
)
>>"%LOG%" echo Yandex proxy: build\web\api\yandex-geocode.js hazir.

echo [3/4] Vercel hesabi kontrol ediliyor...
>>"%LOG%" echo.
>>"%LOG%" echo ===== VERCEL WHOAMI =====
call npx --yes vercel@latest whoami >>"%LOG%" 2>&1
if errorlevel 1 (
  echo Vercel girisi gerekiyor. Tarayici acilirsa hesabinizla giris yapin.
  >>"%LOG%" echo ===== VERCEL LOGIN =====
  call npx --yes vercel@latest login
  if errorlevel 1 (
    echo HATA: Vercel girisi tamamlanamadi.
    >>"%LOG%" echo HATA: Vercel login basarisiz.
    goto :fail
  )
)

echo [4/4] MOTUS internete yayinlaniyor...
echo Ilk yayinlamada Vercel birkac saniye bekletebilir.
>>"%LOG%" echo.
>>"%LOG%" echo ===== VERCEL DEPLOY =====

rem V49: PowerShell pipe/redirection kullanmiyoruz. CMD uzerinden mevcut motus-app
rem projesine link olup build\web klasorunu production'a gonderiyoruz.
set "DEPLOY_OUT=%TEMP%\motus_vercel_output.txt"
if exist "%DEPLOY_OUT%" del /q "%DEPLOY_OUT%" >nul 2>&1

pushd "build\web"

>>"%LOG%" echo ===== VERCEL LINK =====
call npx --yes vercel@latest link --yes --project motus-app --scope darkswagger35-dels-projects >>"%LOG%" 2>&1
if errorlevel 1 (
  popd
  echo HATA: Vercel motus-app projesine baglanamadi.
  goto :fail
)

call npx --yes vercel@latest deploy --prod --yes >"%DEPLOY_OUT%" 2>&1
set "DEPLOY_CODE=%ERRORLEVEL%"

popd

if exist "%DEPLOY_OUT%" (
  type "%DEPLOY_OUT%"
  type "%DEPLOY_OUT%" >>"%LOG%"
)

if not "%DEPLOY_CODE%"=="0" (
  echo HATA: Vercel yayinlama tamamlanamadi. Kod: %DEPLOY_CODE%
  goto :fail
)

echo.
echo =============================================
echo   TAMAM: MOTUS WEB YAYINLANDI
echo =============================================
echo.
echo Yukarida Vercel'in verdigi https://...vercel.app adresi var.
echo Sekreter ve teknikerlere vereceginiz adres odur.
echo.
echo Sonraki yayinlarda yine sadece WEB_YAYINLA.bat dosyasini acmaniz yeterli.
echo.
>>"%LOG%" echo.
>>"%LOG%" echo SONUC: BASARILI
pause
exit /b 0

:fail
echo.
echo =============================================
echo   YAYINLAMA BASARISIZ
echo =============================================
echo Hata ayrintisi: WEB_YAYINLA_LOG.txt
echo Bu pencere kapanmayacak.
echo.
>>"%LOG%" echo.
>>"%LOG%" echo SONUC: BASARISIZ
pause
exit /b 1
