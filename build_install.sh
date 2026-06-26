#!/bin/bash
# Run inside Dockerfile as headless user to install MT5 terminals.

set -e

export DISPLAY=:99
export WINEDEBUG=-all
export WINEPREFIX=/home/headless/.wine
export WINEDLLOVERRIDES="mscoree,mshtml="

# Start virtual display
Xvfb :99 -screen 0 1024x768x24 -ac >/tmp/xvfb_build.log 2>&1 &
XVFB_PID=$!
sleep 2

# Make sure Wine prefix is initialized
wineboot -i >/tmp/wineboot_build.log 2>&1
while pgrep -u headless wineboot >/dev/null 2>&1; do sleep 1; done

# Install generic MetaTrader 5
wine /tmp/mt5-setup/mt5setup.exe /auto >/tmp/mt5_install_build.log 2>&1
wineserver -w

# Install Exness-branded terminal
wine /tmp/mt5-setup/exness5setup.exe /auto >/tmp/exness_install_build.log 2>&1
wineserver -w

# Install XM-branded terminal
wine /tmp/mt5-setup/xmglobal5setup.exe /auto >/tmp/xm_install_build.log 2>&1
wineserver -w

# Cleanup
rm -rf /tmp/mt5-setup
kill "$XVFB_PID" 2>/dev/null || true

echo "Install script finished"
