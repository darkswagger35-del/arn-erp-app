@echo off
rem MOTUS Web yayinlama baslaticisi.
rem /K sayesinde hata olsa bile pencere kapanmaz.
start "MOTUS Web Yayinla" cmd.exe /k ""%~dp0WEB_YAYINLA_IC.bat""
exit /b 0
