import json
import os
import shutil
import sqlite3
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

from . import config

_display_lock = threading.Lock()
_display_counter = [10]


def _next_display():
    with _display_lock:
        while True:
            d = _display_counter[0]
            _display_counter[0] += 1
            if not os.path.exists(f"/tmp/.X{d}-lock"):
                return d


class AccountManager:
    def __init__(self):
        config.ACCOUNTS_DIR.mkdir(parents=True, exist_ok=True)
        config.DATA_DIR.mkdir(parents=True, exist_ok=True)
        self._running: dict[int, dict] = {}
        self._lock = threading.Lock()
        self._init_db()
        with self._conn() as c:
            c.execute("UPDATE accounts SET status='stopped'")

    def _conn(self):
        conn = sqlite3.connect(config.DB_PATH, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        with self._conn() as c:
            c.execute(
                """
                CREATE TABLE IF NOT EXISTS accounts (
                    id       INTEGER PRIMARY KEY AUTOINCREMENT,
                    name     TEXT    NOT NULL,
                    login    TEXT    NOT NULL,
                    password TEXT    NOT NULL,
                    server   TEXT    NOT NULL,
                    symbol   TEXT    DEFAULT 'XAUUSDm',
                    status   TEXT    DEFAULT 'stopped',
                    created  TEXT    DEFAULT (datetime('now'))
                )
                """
            )

    # ---------------------------------------------------------------- CRUD
    def list_accounts(self):
        with self._conn() as c:
            rows = c.execute("SELECT * FROM accounts ORDER BY id").fetchall()
        result = [dict(r) for r in rows]
        with self._lock:
            for acc in result:
                if acc["id"] in self._running:
                    acc["status"] = "running"
        return result

    def get_account(self, acc_id: int) -> dict | None:
        with self._conn() as c:
            row = c.execute("SELECT * FROM accounts WHERE id=?", (acc_id,)).fetchone()
        return dict(row) if row else None

    def add_account(self, name: str, login: str, password: str, server: str, symbol: str = "XAUUSDm") -> int:
        with self._conn() as c:
            cur = c.execute(
                "INSERT INTO accounts (name,login,password,server,symbol) VALUES (?,?,?,?,?)",
                (name, login, password, server, symbol),
            )
            return cur.lastrowid

    def update_account(self, acc_id: int, **kwargs) -> dict | None:
        allowed = {"name", "login", "password", "server", "symbol"}
        updates = {k: v for k, v in kwargs.items() if k in allowed and v is not None}
        if not updates:
            return self.get_account(acc_id)
        with self._conn() as c:
            c.execute(
                "UPDATE accounts SET " + ", ".join(f"{k}=?" for k in updates) + " WHERE id=?",
                (*updates.values(), acc_id),
            )
        return self.get_account(acc_id)

    def delete_account(self, acc_id: int):
        self.stop_account(acc_id)
        with self._conn() as c:
            c.execute("DELETE FROM accounts WHERE id=?", (acc_id,))
        wine_dir = self._wine_dir(acc_id)
        if wine_dir.exists():
            shutil.rmtree(wine_dir, ignore_errors=True)

    # ----------------------------------------------------------- Lifecycle
    def _wine_dir(self, acc_id: int) -> Path:
        return config.ACCOUNTS_DIR / str(acc_id) / "wine"

    def _files_dir(self, acc_id: int) -> Path:
        return config.ACCOUNTS_DIR / str(acc_id) / "files"

    def _install_dir(self, acc_id: int) -> Path:
        return self._wine_dir(acc_id) / "drive_c/Program Files" / f"MT5_Acc{acc_id}"

    def _config_dir(self, acc_id: int) -> Path:
        return self._wine_dir(acc_id) / "drive_c/MT5Config"

    def _config_path(self, acc_id: int) -> Path:
        return self._config_dir(acc_id) / f"acc{acc_id}.ini"

    @staticmethod
    def _primary_terminal(acc: dict) -> Path:
        server = (acc.get("server") or "").lower()
        if "exness" in server:
            target = config.PRIMARY_EXNESS
            label = "Exness"
        elif "xm" in server:
            target = config.PRIMARY_XM
            label = "XM"
        else:
            target = config.PRIMARY_GENERIC
            label = "generic"
        for _ in range(120):
            if (target / "terminal64.exe").exists():
                return target
            time.sleep(2)
        raise RuntimeError(f"{label} terminal is not installed yet. Wait for first-time setup.")

    def _setup_prefix(self, acc_id: int, acc: dict):
        wine_dir = self._wine_dir(acc_id)
        files_dir = self._files_dir(acc_id)
        install_dir = self._install_dir(acc_id)
        files_dir.mkdir(parents=True, exist_ok=True)

        symbol = acc.get("symbol") or "XAUUSDm"

        if not (wine_dir / "drive_c").exists():
            subprocess.run(["cp", "-a", str(config.PRIMARY_WINE), str(wine_dir)], check=True)

        primary_terminal = self._primary_terminal(acc)
        primary_generic = config.PRIMARY_GENERIC

        if not (install_dir / "terminal64.exe").exists():
            install_dir.parent.mkdir(parents=True, exist_ok=True)
            for _ in range(120):
                if (primary_terminal / "terminal64.exe").exists():
                    break
                time.sleep(1)
            else:
                raise RuntimeError("Primary MT5 installation is not ready")

            subprocess.run(["cp", "-a", str(primary_terminal), str(install_dir)], check=True)

            for profiles_root in (install_dir / "Profiles", install_dir / "MQL5/Profiles"):
                charts_default = profiles_root / "Charts/Default"
                if charts_default.is_dir():
                    for fname in charts_default.iterdir():
                        if fname.suffix in (".chr", ".wnd"):
                            fname.unlink()

            liveupdate_path = install_dir / "liveupdate"
            if liveupdate_path.is_dir():
                shutil.rmtree(liveupdate_path, ignore_errors=True)
            elif liveupdate_path.exists():
                liveupdate_path.unlink()
            liveupdate_path.write_text("")

            for stale_path in (
                install_dir / "Config/accounts.dat",
                install_dir / "config/accounts.dat",
                install_dir / "Config/terminal.ini",
                install_dir / "terminal.ini",
            ):
                if stale_path.exists():
                    stale_path.unlink()

        for stale_path in (
            install_dir / "Config/accounts.dat",
            install_dir / "config/accounts.dat",
            install_dir / "Config/terminal.ini",
            install_dir / "terminal.ini",
        ):
            if stale_path.exists():
                stale_path.unlink()

        ea_candidates = [
            primary_generic / "MQL5/Experts/AccountBridge.ex5",
            install_dir / "MQL5/Experts/AccountBridge.ex5",
        ]
        ea_src = next((p for p in ea_candidates if p.is_file()), None)
        ea_dst = install_dir / "MQL5/Experts/AccountBridge.ex5"
        if ea_src:
            ea_dst.parent.mkdir(parents=True, exist_ok=True)
            if not ea_dst.is_file() or ea_src.stat().st_mtime > ea_dst.stat().st_mtime:
                shutil.copy2(ea_src, ea_dst)

        config_dir = self._config_dir(acc_id)
        config_dir.mkdir(parents=True, exist_ok=True)
        config_path = self._config_path(acc_id)
        config_path.write_text(
            f"[Common]\n"
            f"Login={acc['login']}\n"
            f"Password={acc['password']}\n"
            f"Server={acc['server']}\n"
            f"NewsEnable=0\n"
            f"CertInstall=0\n\n"
            f"[Experts]\n"
            f"AllowLiveTrading=1\n"
            f"AllowDllImport=1\n"
            f"Enabled=1\n"
            f"Account=1\n\n"
            f"[StartUp]\n"
            f"Expert=AccountBridge.ex5\n"
            f"Symbol={symbol}\n"
            f"Period=W1\n"
        )

        mql5_files = install_dir / "MQL5/Files"
        mql5_files.parent.mkdir(parents=True, exist_ok=True)
        if mql5_files.is_symlink() or mql5_files.exists():
            if mql5_files.is_dir() and not mql5_files.is_symlink():
                shutil.rmtree(mql5_files)
            else:
                mql5_files.unlink()
        mql5_files.symlink_to(files_dir)

        common_files = install_dir / "Common/Files"
        common_files.parent.mkdir(parents=True, exist_ok=True)
        if common_files.is_symlink() or common_files.exists():
            if common_files.is_dir() and not common_files.is_symlink():
                shutil.rmtree(common_files)
            else:
                common_files.unlink()
        common_files.symlink_to(files_dir)

        appdata_common = (
            wine_dir
            / "drive_c/users/headless/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
        )
        appdata_common.parent.mkdir(parents=True, exist_ok=True)
        if appdata_common.is_symlink() or appdata_common.exists():
            if appdata_common.is_dir() and not appdata_common.is_symlink():
                shutil.rmtree(appdata_common)
            else:
                appdata_common.unlink()
        appdata_common.symlink_to(files_dir)

    def start_account(self, acc_id: int) -> tuple[bool, str]:
        acc = self.get_account(acc_id)
        if not acc:
            return False, "Account not found"
        with self._lock:
            if acc_id in self._running:
                return False, "Already running"

        try:
            self._setup_prefix(acc_id, acc)
        except Exception as e:
            return False, f"Setup failed: {e}"

        display = 1
        wine_dir = self._wine_dir(acc_id)
        install_dir = self._install_dir(acc_id)
        mt5_exe = install_dir / "terminal64.exe"
        config_arg = f"/config:C:\\MT5Config\\acc{acc_id}.ini"

        env = {
            **os.environ,
            "DISPLAY": f":{display}",
            "WINEPREFIX": str(wine_dir),
            "WINEDEBUG": "-all",
        }

        mt5_proc = subprocess.Popen(
            ["wine", str(mt5_exe), "/portable", config_arg],
            env=env,
            cwd=str(install_dir),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        threading.Thread(
            target=self._disable_liveupdate,
            args=(acc_id, wine_dir, install_dir),
            daemon=True,
        ).start()

        with self._lock:
            self._running[acc_id] = {"mt5": mt5_proc, "display": display}
        self._set_status(acc_id, "running")
        return True, f"Started portable MT5 on display :{display}"

    def restart_account(self, acc_id: int) -> tuple[bool, str]:
        self.stop_account(acc_id)
        time.sleep(2)
        return self.start_account(acc_id)

    def _disable_liveupdate(self, acc_id: int, wine_dir: Path, install_dir: Path):
        appdata_terminal = (
            wine_dir / "drive_c/users/headless/AppData/Roaming/MetaQuotes/Terminal"
        )
        webinstall_path = (
            wine_dir / "drive_c/users/headless/AppData/Roaming/MetaQuotes/WebInstall"
        )
        install_origin = f"C:\\Program Files\\MT5_Acc{acc_id}"

        def _block(path: Path):
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            elif path.exists():
                path.unlink()
            path.write_text("")
            path.chmod(0o444)

        try:
            _block(install_dir / "liveupdate")
        except Exception:
            pass
        try:
            _block(webinstall_path)
        except Exception:
            pass

        for _ in range(60):
            time.sleep(1)
            if not appdata_terminal.is_dir():
                continue
            for item in appdata_terminal.iterdir():
                origin_file = item / "origin.txt"
                if not origin_file.exists():
                    continue
                try:
                    origin = origin_file.read_bytes().decode("utf-16-le", "replace").strip("\x00\ufeff")
                except Exception:
                    continue
                if install_origin not in origin:
                    continue
                try:
                    _block(item / "liveupdate")
                except Exception:
                    pass
                return

    def stop_account(self, acc_id: int):
        with self._lock:
            procs = self._running.pop(acc_id, None)
        if procs and procs.get("mt5"):
            try:
                procs["mt5"].terminate()
            except Exception:
                pass
        self._set_status(acc_id, "stopped")

    def _set_status(self, acc_id: int, status: str):
        with self._conn() as c:
            c.execute("UPDATE accounts SET status=? WHERE id=?", (status, acc_id))

    # ----------------------------------------------------------- Data I/O
    def _read_json_file(self, path: Path) -> Any:
        if not path.exists():
            return None
        try:
            return json.loads(path.read_text())
        except Exception:
            return None

    def get_account_data(self, acc_id: int) -> dict:
        files_dir = self._files_dir(acc_id)
        result: dict = {}
        if not files_dir.is_dir():
            return result
        for fname in files_dir.glob("*.json"):
            data = self._read_json_file(fname)
            if data is not None:
                result[fname.stem] = data
        return result

    def get_primary_data(self) -> dict:
        primary_files = (
            config.PRIMARY_WINE
            / "drive_c/users/headless/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
        )
        result: dict = {}
        if not primary_files.is_dir():
            return result
        for fname in primary_files.glob("*.json"):
            data = self._read_json_file(fname)
            if data is not None:
                result[fname.stem] = data
        return result
