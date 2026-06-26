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
# The installers must run as the headless user (same as runtime) with a
# virtual X display.
RUN mkdir -p /tmp/mt5-setup "/home/headless/.wine/drive_c/Program Files" && \
    chown -R headless:headless /tmp/mt5-setup /home/headless/.wine && \
    cd /tmp/mt5-setup && \
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -O mt5setup.exe && \
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/exness.technologies.ltd/mt5/exness5setup.exe" -O exness5setup.exe && \
    wget -q --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "https://download.mql5.com/cdn/web/xm.global.limited/mt5/xmglobal5setup.exe" -O xmglobal5setup.exe && \
    chown -R headless:headless /tmp/mt5-setup

COPY build_install.sh /tmp/build_install.sh
RUN chmod +x /tmp/build_install.sh && runuser -u headless -- /tmp/build_install.sh && rm -f /tmp/build_install.sh

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
