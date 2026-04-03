@echo off
:: Nosia Installation Script for Windows
:: This batch file downloads and runs the PowerShell installation script

echo Downloading Nosia installation script...
powershell -Command "Invoke-WebRequest -Uri 'https://get.nosia.ai/install.ps1' -OutFile 'install.ps1'"

if %ERRORLEVEL% NEQ 0 (
    echo Error downloading installation script
    exit /b 1
)

echo Running installation...
powershell -ExecutionPolicy Bypass -File install.ps1

if %ERRORLEVEL% NEQ 0 (
    echo Installation failed
    exit /b 1
)

echo Installation completed successfully!
