from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import config, market_data
from .account_manager import AccountManager
from .auth import require_token

manager = AccountManager()


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    # On shutdown stop all running accounts
    for acc in manager.list_accounts():
        manager.stop_account(acc["id"])


app = FastAPI(
    title="XM/Exness Ready Linux MetaTrader 5 API",
    description="REST API to manage multiple MetaTrader 5 accounts running inside Docker/Wine.",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ----------------------------------------------------------------- Schemas
class AccountCreate(BaseModel):
    name: str = Field(..., example="XM Account")
    login: str = Field(..., example="168892363")
    password: str = Field(..., example="Essa123$$$")
    server: str = Field(..., example="XMGlobal-MT5 2")
    symbol: str = Field(default="XAUUSDm", example="GOLD")


class AccountUpdate(BaseModel):
    name: str | None = None
    login: str | None = None
    password: str | None = None
    server: str | None = None
    symbol: str | None = None


class Message(BaseModel):
    ok: bool
    message: str


# ----------------------------------------------------------------- Helpers
def _with_data(acc: dict) -> dict:
    acc["data"] = manager.get_account_data(acc["id"])
    return acc


# ----------------------------------------------------------------- Routes
@app.get("/health", tags=["System"])
def health():
    return {"status": "ok", "vnc_enabled": config.VNC_ENABLED}


@app.get("/api/primary", tags=["System"], dependencies=[Depends(require_token)])
def primary_data():
    return manager.get_primary_data()


@app.get("/api/data", tags=["System"], dependencies=[Depends(require_token)])
def all_data():
    return {
        "primary": manager.get_primary_data(),
        "accounts": [_with_data(acc) for acc in manager.list_accounts()],
    }


@app.get("/api/accounts", tags=["Accounts"], dependencies=[Depends(require_token)])
def list_accounts():
    return [_with_data(acc) for acc in manager.list_accounts()]


@app.post("/api/accounts", tags=["Accounts"], dependencies=[Depends(require_token)], status_code=201)
def create_account(payload: AccountCreate):
    acc_id = manager.add_account(
        name=payload.name,
        login=payload.login,
        password=payload.password,
        server=payload.server,
        symbol=payload.symbol,
    )
    return {"id": acc_id}


@app.get("/api/accounts/{acc_id}", tags=["Accounts"], dependencies=[Depends(require_token)])
def get_account(acc_id: int):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    return _with_data(acc)


@app.put("/api/accounts/{acc_id}", tags=["Accounts"], dependencies=[Depends(require_token)])
def update_account(acc_id: int, payload: AccountUpdate):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    manager.update_account(acc_id, **payload.model_dump(exclude_unset=True))
    return _with_data(manager.get_account(acc_id))


@app.delete("/api/accounts/{acc_id}", tags=["Accounts"], dependencies=[Depends(require_token)])
def delete_account(acc_id: int):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    manager.delete_account(acc_id)
    return {"ok": True}


@app.post("/api/accounts/{acc_id}/start", tags=["Lifecycle"], dependencies=[Depends(require_token)])
def start_account(acc_id: int):
    ok, msg = manager.start_account(acc_id)
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    return {"ok": True, "message": msg}


@app.post("/api/accounts/{acc_id}/stop", tags=["Lifecycle"], dependencies=[Depends(require_token)])
def stop_account(acc_id: int):
    manager.stop_account(acc_id)
    return {"ok": True}


@app.post("/api/accounts/{acc_id}/restart", tags=["Lifecycle"], dependencies=[Depends(require_token)])
def restart_account(acc_id: int):
    ok, msg = manager.restart_account(acc_id)
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    return {"ok": True, "message": msg}


@app.get("/api/accounts/{acc_id}/data", tags=["Data"], dependencies=[Depends(require_token)])
def account_data(acc_id: int):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    return manager.get_account_data(acc_id)


@app.get("/api/accounts/{acc_id}/price", tags=["Data"], dependencies=[Depends(require_token)])
def account_price(acc_id: int, symbol: str | None = None):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")

    sym = (symbol or acc.get("symbol") or "XAUUSDm").upper()
    data = manager.get_account_data(acc_id)
    price = data.get(sym)
    source = "mt5"
    if not price:
        price = market_data.get_price_from_yfinance(sym)
        source = "yfinance"
    if not price:
        raise HTTPException(status_code=404, detail=f"No price data for {sym}")
    return {"account_id": acc_id, "symbol": sym, "source": source, "price": price}


@app.get("/api/accounts/{acc_id}/bars/{timeframe}", tags=["Data"], dependencies=[Depends(require_token)])
def account_bars_timeframe(
    acc_id: int,
    timeframe: str,
    symbol: str | None = None,
    count: int = Query(default=100, ge=1, le=market_data.MAX_COUNT),
):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    sym = (symbol or acc.get("symbol") or "XAUUSDm").upper()
    return market_data.get_yfinance_bars(sym, timeframe, count)


@app.get("/api/accounts/{acc_id}/bars/{symbol}/{timeframe}", tags=["Data"], dependencies=[Depends(require_token)])
def account_bars_symbol_timeframe(
    acc_id: int,
    symbol: str,
    timeframe: str,
    count: int = Query(default=100, ge=1, le=market_data.MAX_COUNT),
):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    return market_data.get_yfinance_bars(symbol.upper(), timeframe, count)


@app.get("/api/accounts/{acc_id}/positions", tags=["Trading"], dependencies=[Depends(require_token)])
def account_positions(acc_id: int):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    data = manager.get_account_data(acc_id)
    return data.get("positions", [])


@app.get("/api/accounts/{acc_id}/orders", tags=["Trading"], dependencies=[Depends(require_token)])
def account_orders(acc_id: int):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    data = manager.get_account_data(acc_id)
    return data.get("orders", [])


@app.get("/api/accounts/{acc_id}/history", tags=["Trading"], dependencies=[Depends(require_token)])
def account_history(acc_id: int, limit: int = Query(default=50, ge=1, le=500)):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    data = manager.get_account_data(acc_id)
    history = data.get("history", [])
    return history[:limit]
