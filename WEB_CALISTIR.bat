@echo off
rem Bu dosya sadece kalici CMD penceresini acar.
rem /K sayesinde hata olsa bile pencere kendi kendine kapanmaz.
start "MOTUS Web" cmd.exe /k ""%~dp0WEB_CALISTIR_IC.bat""
exit /b 0
