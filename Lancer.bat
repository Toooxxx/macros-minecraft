@echo off
rem Lance le menu Macros Minecraft (le dossier peut etre n importe ou).
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Ferme-canne.ps1"
