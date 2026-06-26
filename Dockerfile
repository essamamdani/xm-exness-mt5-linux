# -----------------------------------------------------------------------------
# XM/Exness Ready Linux MetaTrader 5 API
# Author: Essa Mamdani
# Credits: Based on hudsonventura/MT5_Docker (https://github.com/hudsonventura/MT5_Docker)
# -----------------------------------------------------------------------------

FROM hudsonventura/mt5:2.3

USER root

# Install Python, FastAPI stack, Xvfb (headless display) and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip \
    xvfb xauth curl \
    && rm -rf /var/lib/apt/lists/*

# Pre-install broker-branded terminals so first container startup is fast.
# The installers need an X display; Xvfb provides a virtual one during build.
RUN mkdir -p /tmp/mt5-setup /home/headless/.wine/drive_c/Program\ Files && \
    cd /tmp/mt5-setup && \
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -O mt5setup.exe && \
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/exness.technologies.ltd/mt5/exness5setup.exe" -O exness5setup.exe && \
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/xm.global.limited/mt5/xmglobal5setup.exe" -O xmglobal5setup.exe

RUN Xvfb :99 -screen 0 1024x768x24 -ac >/tmp/xvfb_build.log 2>&1 & \
    export DISPLAY=:99 WINEDEBUG=-all WINEPREFIX=/home/headless/.wine && \
    wineboot -i >/tmp/wineboot_build.log 2>&1 && \
    sleep 5 && \
    wine /tmp/mt5-setup/mt5setup.exe /auto >/tmp/mt5_install_build.log 2>&1 && \
    wineserver -w && \
    wine /tmp/mt5-setup/exness5setup.exe /auto >/tmp/exness_install_build.log 2>&1 && \
    wineserver -w && \
    wine /tmp/mt5-setup/xmglobal5setup.exe /auto >/tmp/xm_install_build.log 2>&1 && \
    wineserver -w && \
    rm -rf /tmp/mt5-setup && \
    kill $(cat /tmp/.X99-lock 2>/dev/null) 2>/dev/null || true && \
    chown -R headless:headless /home/headless/.wine

WORKDIR /opt/mt5api

# Python dependencies
COPY requirements.txt .
RUN pip3 install --break-system-packages --ignore-installed -r requirements.txt

# Application code
COPY app/ ./app/
COPY mql5/ ./mql5/
COPY templates/ ./templates/
COPY static/ ./static/
COPY start.sh install_terminals.sh ./
RUN chmod +x start.sh install_terminals.sh

# Move the original MT5_Docker entrypoint out of the way so we can wrap it
RUN mv /start.sh /start_mt5_base.sh

# Data directory (persist accounts, Wine prefix, DB)
RUN mkdir -p /data/accounts /data/files && chown -R headless:headless /data /opt/mt5api

# VNC/noVNC ports and API port
EXPOSE 5901 6901 8000

USER headless

CMD ["/opt/mt5api/start.sh"]
