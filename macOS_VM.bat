@echo off
title macOS Sequoia VM Launcher
echo ==========================================
echo   macOS Sequoia VM - Quick Launcher
echo ==========================================
echo.
echo Starting VM (this takes about 30 seconds)...
echo.
wsl -u su -e bash /mnt/e/macos-kvm/start_vm.sh
echo.
echo ==========================================
echo   Connect with VNC: 127.0.0.1:5901
echo   macOS Password: 214314
echo ==========================================
echo.
pause
