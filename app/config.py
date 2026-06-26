import os
from pathlib import Path

DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
ACCOUNTS_DIR = DATA_DIR / "accounts"
DB_PATH = DATA_DIR / "accounts.db"
PRIMARY_WINE = Path(os.environ.get("PRIMARY_WINE", "/home/headless/.wine"))
API_PORT = int(os.environ.get("API_PORT", "8000"))
API_HOST = os.environ.get("API_HOST", "0.0.0.0")
API_TOKEN = os.environ.get("API_TOKEN", "")
VNC_ENABLED = os.environ.get("VNC_ENABLED", "true").lower() in ("1", "true", "yes")
VNC_PASSWORD = os.environ.get("VNC_PASSWORD", "password")
SCREEN_RESOLUTION = os.environ.get("SCREEN_RESOLUTION", "1024x768")

PRIMARY_GENERIC = PRIMARY_WINE / "drive_c/Program Files/MetaTrader 5"
PRIMARY_EXNESS = PRIMARY_WINE / "drive_c/Program Files/MetaTrader 5 EXNESS"
PRIMARY_XM = PRIMARY_WINE / "drive_c/Program Files/XM Global MT5"
