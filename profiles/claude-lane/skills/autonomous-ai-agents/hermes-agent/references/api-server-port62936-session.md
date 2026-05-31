# API Server Enablement — Port 62936 Session

**Session Date:** May 04, 2026  
**User:** Josh (frostthejack/lunedecente)  
**Issue:** Enabling Hermes API Server on custom port 62936 without API key

## Problem

User attempting to `curl http://localhost:62936/v1/models` from Windows PowerShell against Hermes running in WSL2. The gateway service was running but the API server component was not enabled, so port 62936 (and default 8642) were closed.

## Root Cause

The Hermes gateway service (messaging platforms) and the API server (OpenAI-compatible `/v1` endpoints) are separate components. The API server is **opt-in** and requires explicit configuration via environment variables.

## Solution Applied

1. **Added to `~/.hermes/.env`:**
   ```bash
   API_SERVER_ENABLED=true
   API_SERVER_PORT=62936
   # No API_SERVER_KEY = allows all requests (local-only)
   ```

2. **Restarted gateway:**
   ```bash
   systemctl --user restart hermes-gateway
   ```

3. **Verified:**
   ```bash
   curl http://127.0.0.1:62936/v1/models
   ```
   Returns: `{"object":"list","data":[{"id":"hermes-agent",...}]}`

## Key Technical Details

### Binding Address
- API server binds to `127.0.0.1` by default (configurable via `API_SERVER_HOST`)
- From WSL: access via `127.0.0.1` or `localhost`
- From Windows PowerShell: use `127.0.0.1:62936` (works via WSL bridge)

### Authentication
- When `API_SERVER_KEY` is **not set**, all requests are allowed without authentication
- Log warning: `⚠️ No API key configured. All requests will be accepted without authentication.`
- Suitable for **local development only**
- For production: set `API_SERVER_KEY=<secret>` and include `Authorization: Bearer <secret>` header

### Port Selection
- Default: `8642`
- Custom: Set `API_SERVER_PORT=<port>` in `.env`
- Override per-platform in `config.yaml` via `platforms.api_server.extra.port`

### Available Endpoints
- `GET /v1/models` - List models
- `POST /v1/chat/completions` - Chat completions
- `POST /v1/responses` - Responses API (stateful)
- `GET /v1/responses/{id}` - Retrieve response
- `DELETE /v1/responses/{id}` - Delete response
- `GET /v1/capabilities` - Capabilities

## Troubleshooting Notes

### Gateway Crashes (exit 75/TEMPFAIL)
If gateway fails to start, check:
```bash
journalctl --user -u hermes-gateway --no-pager -n 30
cat ~/.hermes/logs/gateway.log | tail -50
```

Common causes:
- Lingering hermes processes conflicting (`hermes gateway run --replace`)
- Port already in use
- Missing dependencies

### Port Not Opening
Verify service is running:
```bash
systemctl --user status hermes-gateway
ss -tlnp | grep 62936
```

Check API server logs:
```bash
grep -i "api_server" ~/.hermes/logs/gateway.log
```

### WSL/Windows Networking
- From Windows: use `127.0.0.1` (not `localhost`) in PowerShell/curl
- WSL2 networking is bridged; `127.0.0.1` in WSL is accessible from Windows host
- If issues persist, check Windows Firewall blocking `vEthernet (WSL)` interface

## Security Considerations

⚠️ **Warning:** Without `API_SERVER_KEY`, the endpoint is **completely open** to anyone who can reach the port. Only use this configuration on trusted local machines.

### Recommended Production Setup
```bash
# .env
API_SERVER_ENABLED=true
API_SERVER_KEY=your-secure-random-key-here
API_SERVER_PORT=8642
```

Then use:
```bash
curl http://127.0.0.1:8642/v1/models \
  -H "Authorization: Bearer your-secure-random-key-here"
```

## Session Outcome

✅ API server enabled on port 62936  
✅ No authentication required (local dev)  
✅ `/v1/models` endpoint responding correctly  
✅ Chat completions working (`POST /v1/chat/completions`)  
✅ Gateway service running and stable  
