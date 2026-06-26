# XM/Exness Ready Linux MetaTrader 5

A clean, open-source Docker image that runs **MetaTrader 5** on Linux via Wine and exposes a full **REST API** to manage multiple accounts, read live prices, fetch chart bars, and inspect positions/orders/history.

**Author:** Essa Mamdani  
**Credits:** Based on the excellent [hudsonventura/MT5_Docker](https://github.com/hudsonventura/MT5_Docker) base image.

---

## Features

- **Multiple accounts** — Exness, XM, or any MT5 broker in one container.
- **Broker-branded terminals** — Auto-installs Exness and XM terminals so login certificates/symbols work out of the box.
- **Live price feed** — Real-time bid/ask from MT5.
- **Chart bars** — `1m`, `5m`, `15m`, `30m`, `1h`, `4h`, `1d`, `1w`, `1mo` via `yfinance` fallback.
- **Account details** — balance, equity, margin, leverage, portfolio, spread.
- **Trading data** — open positions, pending orders, closed order history.
- **Bearer-token auth** — Mandatory `API_TOKEN` header authentication.
- **VNC optional** — Enable only when you need a GUI; otherwise the container runs headless.
- **OpenAPI docs** — Auto-generated at `/docs` and `/openapi.json`.

---

## Quick Start

1. **Clone the repo and copy the env file:**

```bash
git clone https://github.com/essamamdani/xm-exness-mt5-linux.git
cd xm-exness-mt5-linux
cp .env.example .env
# Edit .env and set a strong API_TOKEN
```

2. **Start the stack:**

```bash
# API only (headless)
docker compose -f docker-compose.dev.yml up -d

# API + VNC/noVNC
docker compose -f docker-compose.dev.yml -f docker-compose.vnc.yml up -d
```

3. **OpenAPI docs:**

```
http://localhost:8000/docs
http://localhost:8000/openapi.json
```

4. **VNC (if enabled):**

```
Browser: http://localhost:6901/vnc.html
VNC:     localhost:5901
Password: the VNC_PASSWORD from .env
```

---

## API Authentication

Every `/api/*` endpoint requires the header:

```
Authorization: Bearer <API_TOKEN>
```

`API_TOKEN` is read from `.env` and is mandatory.

---

## Example Usage

### Add an account

```bash
curl -X POST http://localhost:8000/api/accounts \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "XM Demo",
    "login": "168892363",
    "password": "Essa123$$$",
    "server": "XMGlobal-MT5 2",
    "symbol": "GOLD"
  }'
```

### Start the account

```bash
curl -X POST http://localhost:8000/api/accounts/1/start \
  -H "Authorization: Bearer $API_TOKEN"
```

### Get live price

```bash
curl http://localhost:8000/api/accounts/1/price \
  -H "Authorization: Bearer $API_TOKEN"
```

### Get chart bars

```bash
# 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w, 1mo
curl "http://localhost:8000/api/accounts/1/bars/GOLD/1m?count=100" \
  -H "Authorization: Bearer $API_TOKEN"
```

### Account data, positions, orders, history

```bash
curl http://localhost:8000/api/accounts/1/data      -H "Authorization: Bearer $API_TOKEN"
curl http://localhost:8000/api/accounts/1/positions -H "Authorization: Bearer $API_TOKEN"
curl http://localhost:8000/api/accounts/1/orders    -H "Authorization: Bearer $API_TOKEN"
curl http://localhost:8000/api/accounts/1/history   -H "Authorization: Bearer $API_TOKEN"
```

---

## Supported Symbols

| Broker | Typical gold symbol | Typical forex |
|--------|---------------------|---------------|
| Exness | `XAUUSDm` / `XAUUSDr` | `EURUSDm` |
| XM     | `GOLD` / `GOLDmicro`  | `EURUSD` |

Always use the exact symbol name shown in your broker's Market Watch.

---

## VNC

VNC runs inside the container regardless, but the ports are only published when you add `docker-compose.vnc.yml`. This keeps the default setup headless and secure.

---

## License

MIT — open source. Pull requests welcome.
