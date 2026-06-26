import datetime as dt
from typing import Any

try:
    import yfinance as yf
except Exception:  # pragma: no cover
    yf = None

# Map our timeframe labels to yfinance interval strings
TIMEFRAME_MAP = {
    "1m": "1m",
    "5m": "5m",
    "15m": "15m",
    "30m": "30m",
    "1h": "1h",
    "4h": "1h",   # yfinance has no native 4h; we return 1h bars for now
    "1d": "1d",
    "1w": "1wk",
    "1mo": "1mo",
    "1y": "1mo",  # alias
}

# yfinance restricts how far back each intraday interval can go.
PERIOD_MAP = {
    "1m": "7d",
    "5m": "60d",
    "15m": "60d",
    "30m": "60d",
    "1h": "730d",
}

DEFAULT_COUNT = 100
MAX_COUNT = 5000


def _normalize_symbol(symbol: str) -> str:
    """Try to map common CFD/forex symbols to yfinance tickers."""
    sym = symbol.upper().strip()
    mapping = {
        "XAUUSD": "GC=F",
        "GOLD": "GC=F",
        "XAGUSD": "SI=F",
        "SILVER": "SI=F",
        "USOIL": "CL=F",
        "OIL": "CL=F",
        "BRENT": "BZ=F",
        "BTCUSD": "BTC-USD",
        "ETHUSD": "ETH-USD",
    }
    if sym in mapping:
        return mapping[sym]
    # For forex pairs like EURUSD -> EURUSD=X
    if len(sym) == 6 and sym[:3].isalpha() and sym[3:].isalpha():
        return sym + "=X"
    return sym


def get_yfinance_bars(symbol: str, timeframe: str, count: int = DEFAULT_COUNT) -> dict[str, Any]:
    if yf is None:
        raise RuntimeError("yfinance is not installed")

    tf = TIMEFRAME_MAP.get(timeframe, timeframe)
    ticker = _normalize_symbol(symbol)
    max_bars = min(count, MAX_COUNT)

    # yfinance limits: intraday data only for limited look-back windows.
    period = PERIOD_MAP.get(tf, "max")

    try:
        hist = yf.Ticker(ticker).history(period=period, interval=tf)
    except Exception as e:
        raise RuntimeError(f"yfinance request failed for {symbol} ({timeframe}): {e}")

    if hist is None or hist.empty:
        raise RuntimeError(f"No yfinance data for {symbol} ({timeframe}). The provider may be rate-limited or the symbol is unsupported.")

    hist = hist.tail(max_bars).reset_index()
    if "Datetime" in hist.columns:
        hist.rename(columns={"Datetime": "Date"}, inplace=True)
    if "Date" in hist.columns:
        hist["Date"] = hist["Date"].dt.strftime("%Y-%m-%dT%H:%M:%S")

    records = hist[["Date", "Open", "High", "Low", "Close", "Volume"]].to_dict(orient="records")
    return {
        "source": "yfinance",
        "symbol": symbol,
        "timeframe": timeframe,
        "count": len(records),
        "bars": records,
    }


def get_price_from_yfinance(symbol: str) -> dict[str, Any] | None:
    try:
        data = get_yfinance_bars(symbol, "1m", count=1)
        bar = data["bars"][-1]
        return {
            "symbol": symbol,
            "bid": round(float(bar["Close"]), 5),
            "ask": round(float(bar["Close"]), 5),
            "last": round(float(bar["Close"]), 5),
            "source": "yfinance",
        }
    except Exception:
        return None
