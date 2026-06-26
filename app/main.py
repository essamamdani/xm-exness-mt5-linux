from contextlib import asynccontextmanager
from typing import Any, Literal

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


@app.exception_handler(RuntimeError)
async def runtime_error_handler(request, exc):
    raise HTTPException(status_code=503, detail=str(exc))


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


class OrderCreate(BaseModel):
    action: Literal[
        "market_buy",
        "market_sell",
        "buy_limit",
        "sell_limit",
        "buy_stop",
        "sell_stop",
    ] = Field(..., example="market_buy")
    symbol: str = Field(..., example="GOLD")
    volume: float = Field(..., gt=0, example=0.1)
    price: float | None = Field(None, example=4080.0)
    sl: float = Field(0.0, example=0.0)
    tp: float = Field(0.0, example=0.0)
    deviation: int = Field(10, example=10)
    comment: str = Field("", example="API order")
    magic: int = Field(0, example=123456)


class PositionModify(BaseModel):
    sl: float | None = Field(None, example=4050.0)
    tp: float | None = Field(None, example=4150.0)


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
def _get_bars(acc_id: int, symbol: str, timeframe: str, count: int):
    # Prefer live MT5 bar data written by the EA.
    mt5_key = f"bars_{timeframe.lower()}"
    data = manager.get_account_data(acc_id)
    mt5_bars = data.get(mt5_key)
    if mt5_bars and isinstance(mt5_bars, dict) and mt5_bars.get("bars"):
        bars = mt5_bars["bars"][-count:]
        return {
            "source": "mt5",
            "symbol": symbol,
            "timeframe": timeframe,
            "count": len(bars),
            "bars": bars,
        }
    # Fall back to yfinance if MT5 has no bars for this timeframe.
    return market_data.get_yfinance_bars(symbol, timeframe, count)


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
    return _get_bars(acc_id, sym, timeframe, count)


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
    return _get_bars(acc_id, symbol.upper(), timeframe, count)


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


# ----------------------------------------------------------------- Trading
def _assert_account_running(acc_id: int):
    acc = manager.get_account(acc_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    data = manager.get_account_data(acc_id)
    account = data.get("account")
    if not account:
        raise HTTPException(status_code=503, detail="MT5 account data not available yet; wait for login")
    return acc


@app.post("/api/accounts/{acc_id}/orders", tags=["Trading"], dependencies=[Depends(require_token)], status_code=201)
def create_order(acc_id: int, payload: OrderCreate):
    _assert_account_running(acc_id)
    if payload.action in ("buy_limit", "sell_limit", "buy_stop", "sell_stop") and payload.price is None:
        raise HTTPException(status_code=400, detail="price is required for pending orders")

    command = payload.model_dump()
    command_id = manager.send_trade_command(acc_id, command)
    result = manager.wait_trade_result(acc_id, command_id, timeout=15.0)
    if result is None:
        raise HTTPException(status_code=504, detail="Timeout waiting for MT5 EA to process order")
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("message", "Order failed"))
    return result


@app.put("/api/accounts/{acc_id}/positions/{ticket}", tags=["Trading"], dependencies=[Depends(require_token)])
def modify_position_sl_tp(acc_id: int, ticket: int, payload: PositionModify):
    _assert_account_running(acc_id)
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="sl or tp must be provided")
    command = {"action": "modify_sl", "ticket": ticket, **updates}
    command_id = manager.send_trade_command(acc_id, command)
    result = manager.wait_trade_result(acc_id, command_id, timeout=15.0)
    if result is None:
        raise HTTPException(status_code=504, detail="Timeout waiting for MT5 EA to process SL/TP modification")
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("message", "SL/TP modification failed"))
    return result


@app.delete("/api/accounts/{acc_id}/orders/{ticket}", tags=["Trading"], dependencies=[Depends(require_token)])
def close_or_cancel_order(
    acc_id: int,
    ticket: int,
    type: Literal["position", "pending"] = Query(..., description="Close a position or cancel a pending order"),
):
    _assert_account_running(acc_id)
    action = "close" if type == "position" else "cancel"
    command_id = manager.send_trade_command(acc_id, {"action": action, "ticket": ticket})
    result = manager.wait_trade_result(acc_id, command_id, timeout=15.0)
    if result is None:
        raise HTTPException(status_code=504, detail="Timeout waiting for MT5 EA to process close/cancel")
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("message", "Close/cancel failed"))
    return result
