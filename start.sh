#!/bin/bash
# XM/Exness Ready Linux MetaTrader 5 API — container startup

# Do not exit on error from helper scripts; the API should stay up.
# set -e

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   XM/Exness Ready Linux MetaTrader 5 API — by Essa Mamdani   ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

# Default env
export API_PORT=${API_PORT:-8000}
export API_HOST=${API_HOST:-0.0.0.0}
export DATA_DIR=${DATA_DIR:-/data}
export VNC_ENABLED=${VNC_ENABLED:-true}

# The base MT5_Docker image provides Wine, VNC and generic MT5 installer.
# We keep it running in the background so the Wine prefix + primary terminal
# are ready, then install broker-branded terminals and start the REST API.
if [ -f /start_mt5_base.sh ]; then
    echo "  ⏳  Starting base MT5/Wine environment..."
    /bin/bash /start_mt5_base.sh >/tmp/mt5_base.log 2>&1 &
    BASE_PID=$!
else
    echo "  ⚠  Base MT5 startup script not found; assuming environment is ready"
    BASE_PID=""
fi

# Wait for X display (base script starts VNC/Xvfb on :1)
export DISPLAY=:1
for i in $(seq 1 120); do
    if xset q >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! xset q >/dev/null 2>&1; then
    echo "  ✘  X display not ready"
    exit 1
fi
echo "  ✔  X display ready"

# Wait for the generic MetaTrader 5 terminal to be installed
MT5_EXE="/home/headless/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
for i in $(seq 1 180); do
    if [ -f "$MT5_EXE" ]; then
        break
    fi
    sleep 2
done
if [ ! -f "$MT5_EXE" ]; then
    echo "  ✘  Generic MetaTrader 5 not installed"
    exit 1
fi

# Install Exness & XM branded terminals if missing
bash /opt/mt5api/install_terminals.sh || true

# Copy enhanced AccountBridge EA into the generic terminal MQL5 tree
# so every cloned account gets the latest version.
EA_SRC="/opt/mt5api/mql5/AccountBridge.mq5"
EA_DST="/home/headless/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/AccountBridge.mq5"
if [ -f "$EA_SRC" ]; then
    mkdir -p "$(dirname "$EA_DST")"
    cp -f "$EA_SRC" "$EA_DST"
fi

# Ensure data directories exist
mkdir -p "$DATA_DIR/accounts" "$DATA_DIR/files"

echo ""
echo "  ✔  Starting REST API on $API_HOST:$API_PORT"
echo ""

# Run uvicorn (FastAPI).  The API manages per-account MT5 processes.
cd /opt/mt5api
exec uvicorn app.main:app --host "$API_HOST" --port "$API_PORT" --log-level info
