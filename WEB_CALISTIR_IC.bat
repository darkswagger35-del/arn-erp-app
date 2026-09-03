@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title MOTUS Web - Yerel Test

set "LOG=%~dp0WEB_CALISTIR_LOG.txt"
>"%LOG%" echo MOTUS WEB CALISTIRMA LOGU
>>"%LOG%" echo Tarih: %date% %time%
>>"%LOG%" echo Klasor: %cd%
>>"%LOG%" echo.

echo.
echo =============================================
echo   MOTUS WEB - YEREL TEST V45
echo =============================================
echo.

if not exist "%~dp0pubspec.yaml" (
  echo HATA: pubspec.yaml bulunamadi.
  echo ZIP dosyasinin ICINDEN calistirmayin.
  echo Once ZIP'e sag tik ^> Tumunu Ayikla deyin.
  echo Sonra cikartilan klasordeki WEB_CALISTIR.bat'i acin.
  >>"%LOG%" echo HATA: pubspec.yaml bulunamadi. ZIP icinden calistirilmis olabilir.
  goto :error_no_code
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo HATA: Flutter PATH icinde bulunamadi.
  >>"%LOG%" echo HATA: Flutter PATH icinde bulunamadi.
  goto :error_no_code
)

echo [1/3] Flutter kontrol ediliyor...
call flutter --version >>"%LOG%" 2>&1
if errorlevel 1 goto :error

rem V44 logunda flutter config --enable-web ayari basariyla yazildi fakat komut
rem exit code 1 dondurdu. Web zaten etkin oldugu icin bu komutu tekrar CALISTIRMIYORUZ.
>>"%LOG%" echo.
>>"%LOG%" echo Web ayari: flutter config --enable-web ATLANDI ^(zaten etkin^).

echo [2/3] Paketler hazirlaniyor...
call flutter pub get >>"%LOG%" 2>&1
if errorlevel 1 goto :error

echo [3/3] Chrome'da MOTUS baslatiliyor...
echo Ilk acilis biraz surebilir. Lutfen bu pencereyi kapatmayin.
echo.
>>"%LOG%" echo.
>>"%LOG%" echo ===== FLUTTER RUN =====
call flutter run -d chrome --dart-define-from-file=config/dev.json >>"%LOG%" 2>&1
if errorlevel 1 goto :error

echo.
echo MOTUS Web normal sekilde sonlandi.
echo Bu pencere /K ile acildigi icin kapanmayacak.
echo Cikmak isterseniz: exit
goto :eof

:error
set "ERR=%errorlevel%"
>>"%LOG%" echo.
>>"%LOG%" echo SON HATA KODU: %ERR%
echo.
echo =============================================
echo HATA: MOTUS Web baslatilamadi. Kod: %ERR%
echo =============================================
echo.
echo Hata ayrintisi asagida ve WEB_CALISTIR_LOG.txt dosyasinda:
echo.
type "%LOG%"
echo.
echo Pencere acik kalacak. Bu metnin ekran goruntusunu veya log dosyasini atin.
echo Cikmak isterseniz: exit
goto :eof

:error_no_code
>>"%LOG%" echo.
>>"%LOG%" echo SON HATA KODU: ON KONTROL
echo.
echo Hata ayrintisi: %LOG%
echo Pencere acik kalacak. Cikmak isterseniz: exit
goto :eof
