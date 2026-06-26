#!/bin/bash
# Install broker-branded terminals if missing.
# These terminals carry the correct certificates, symbols and servers.dat.

# Do not exit on error — try both terminals independently.

export DISPLAY=${DISPLAY:-:1}
export WINEDEBUG=-all

WINE_DIR="/home/headless/.wine"
EXNESS_DIR="$WINE_DIR/drive_c/Program Files/MetaTrader 5 EXNESS"
XM_DIR="$WINE_DIR/drive_c/Program Files/XM Global MT5"

install_exness() {
    if [ -f "$EXNESS_DIR/terminal64.exe" ]; then
        echo "✔ Exness terminal already installed"
        return
    fi
    echo "⏳ Installing Exness terminal..."
    mkdir -p /tmp/exness-setup
    cd /tmp/exness-setup
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/exness.technologies.ltd/mt5/exness5setup.exe" \
        -O exness5setup.exe
    wine exness5setup.exe /auto >/tmp/exness_install.log 2>&1 || true
    wineserver -w || true
    rm -rf /tmp/exness-setup
    if [ -f "$EXNESS_DIR/terminal64.exe" ]; then
        echo "✔ Exness terminal installed"
    else
        echo "✘ Exness terminal install failed — see /tmp/exness_install.log"
    fi
}

install_xm() {
    if [ -f "$XM_DIR/terminal64.exe" ]; then
        echo "✔ XM terminal already installed"
        return
    fi
    echo "⏳ Installing XM terminal..."
    mkdir -p /tmp/xm-setup
    cd /tmp/xm-setup
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/xm.global.limited/mt5/xmglobal5setup.exe" \
        -O xmglobal5setup.exe
    wine xmglobal5setup.exe /auto >/tmp/xm_install.log 2>&1 || true
    wineserver -w || true
    rm -rf /tmp/xm-setup
    if [ -f "$XM_DIR/terminal64.exe" ]; then
        echo "✔ XM terminal installed"
    else
        echo "✘ XM terminal install failed — see /tmp/xm_install.log"
    fi
}

install_exness
install_xm
