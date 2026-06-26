#!/bin/bash
# Run inside Dockerfile as headless user to install MT5 terminals.

export DISPLAY=:99
export WINEDEBUG=-all
export WINEPREFIX=/home/headless/.wine
export WINEDLLOVERRIDES="mscoree,mshtml="

# Start virtual display
Xvfb :99 -screen 0 1024x768x24 -ac >/tmp/xvfb_build.log 2>&1 &
sleep 2

# Make sure Wine prefix is initialized
wineboot -i >/tmp/wineboot_build.log 2>&1
while pgrep -u headless wineboot >/dev/null 2>&1; do sleep 1; done

# Install generic MetaTrader 5
wine /tmp/mt5-setup/mt5setup.exe /auto >/tmp/mt5_install_build.log 2>&1 || true
wineserver -w || true

# Install Exness-branded terminal
wine /tmp/mt5-setup/exness5setup.exe /auto >/tmp/exness_install_build.log 2>&1 || true
wineserver -w || true

# Install XM-branded terminal
wine /tmp/mt5-setup/xmglobal5setup.exe /auto >/tmp/xm_install_build.log 2>&1 || true
wineserver -w || true

# Cleanup
rm -rf /tmp/mt5-setup
kill $(cat /tmp/.X99-lock 2>/dev/null) 2>/dev/null || true

echo "Install script finished"
