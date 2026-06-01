# Hermes-Trading Audit: Alpaca API Usage

**Audit Date:** 2026-05-31  
**Auditor:** OWL (Hermes Agent)  
**System:** Hermes-Trading v0.1 (Phase 0 — paper trading / dev infrastructure)  
**Path:** `C:\Users\luned\Documents\Projects\Hermes-Trading\`

---

## Executive Answer

**The Hermes-Trading system does NOT need Alpaca API keys to function.**  
It runs entirely on **free data sources** (yfinance, SEC EDGAR). The word "Alpaca" appears in the entire codebase only as a **comment** and a **rate-limit placeholder** — no Alpaca SDK is imported, no Alpaca API calls are made, and no Alpaca credentials are configured anywhere.

---

## Detailed Findings

### 1. Alpaca SDK / API Calls

**Finding: NOT USED**

- No `import alpaca` or `from alpaca...` anywhere in any .py file.
- No `tradeapi`, `REST`, `Stream`, or `StreamConn` imports (zero matches).
- No Alpaca API endpoint URLs (e.g. `api.alpaca.markets`, `data.alpaca.markets`) in any file.

The word "Alpaca" appears exactly **twice** in the entire codebase, both in `trading/data.py`:

| Line | Context | Type |
|------|---------|------|
| 3 | `"""Uses only free data sources: yfinance, Alpaca (free tier), FRED, SEC EDGAR."""` | Docstring comment only |
| 35 | `'alpaca': 0.3,        # 0.3 sec between Alpaca requests` | Rate-limit dict key + comment |

Neither of these results in any actual Alpaca API call. The rate-limit entry is dead code — no function ever calls `_rate_limit('alpaca')`.

### 2. No Alpaca Credentials Anywhere

- **No `.env` files found** in the entire project (0 results).
- **No `config.toml` file found** in the codebase (referenced in PHASE_0_PLAN.md as task 0.7 but never created).
- **No API key references** (`api_key`, `apikey`, `secret_key`) in any .py, .toml, .json, .yaml, .cfg, or .ini file.
- **No `__init__.py` exports** related to Alpaca or any broker.

### 3. Actual Dependencies

From `requirements.txt` (the only non-empty requirements file):

```
yfinance>=0.2.28
requests>=2.31.0
pandas>=2.0.0
numpy>=1.24.0
```

`requirements_full.txt` exists but is **empty** (0 bytes).

**Notably absent from requirements:** `alpaca-trade-api`, `alpaca-py`, or any Alpaca package.

### 4. What Data Sources Are Actually Used

Based on code analysis of `trading/data.py` (310 lines):

| Source | Used For | Rate Limit |
|--------|----------|------------|
| **yfinance** | Stock prices (`get_stock_price`), historical data (`get_historical_prices`), VIX/SPY/QQQ, sector ETFs, earnings calendar, breakout screening | 1.0 sec |
| **SEC EDGAR** (via `urllib`) | Insider trades (Form 4 filings), CIK lookup | 0.1–0.5 sec |
| **FRED** | Mentioned as a future rate-limit slot, but no FRED API calls detected in code | 0.5 sec (placeholder) |
| **Alpaca** | Not used. Only referenced in a docstring and rate-limit placeholder | 0.3 sec (dead code) |

### 5. What the System Actually Does

The codebase is a **Phase 0 paper-trading infrastructure** with:

- **`data.py`** — Market data fetcher (yfinance + SEC EDGAR only)
- **`signals.py`** — Signal detection (Earnings PEAD, Fed drift, technical breakout)
- **`risk.py`** — 8-gate risk engine with hardcoded limits
- **`journal.py`** — Trade journal, P&L tracking (SQLite-based, hypothetical $100 account)
- **`database.py`** — SQLite WAL with 9 tables, initialized with $100 baseline
- **`gate_engine.py`** — 5-gate decision framework for trade signals

**All positions, trades, and P&L are stored in a local SQLite database.** No broker API (Alpaca or otherwise) has been integrated. The `__init__.py` exports risk functions — no broker functions.

### 6. Rail(Railway) Deployment Implications

- The system has **no `railway.toml`**, **no `Dockerfile`**, and **no `fly.toml`** in the codebase.  
- No containerization or deployment configuration exists yet.
- If deploying to Railway, **no Alpaca environment variables are needed**.
- The only runtime dependencies are: `yfinance`, `requests`, `pandas`, `numpy` (all free, no API keys).

---

## Conclusion

| Question | Answer |
|----------|--------|
| Does the system import the Alpaca SDK? | **No** |
| Does the system make Alpaca API calls? | **No** |
| Are Alpaca API keys configured anywhere? | **No** |
| Does the system NEED Alpaca API keys? | **No** |
| What data source does it actually use? | **yfinance** (free, no keys) + **SEC EDGAR** (free, no keys) |
| Is the system paper-trading only? | **Yes** (Phase 0 — hypothetical $100 account in SQLite) |
| Can it run on Railway without Alpaca keys? | **Yes** — no Alpaca keys needed |

**The system runs 100% on free yfinance data. Alpaca is mentioned only in comments/planning — it is not integrated and not required.**
