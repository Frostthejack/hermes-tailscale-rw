# API Server Discovery & Enablement Pattern

## Diagnostic Commands

### Check if API Server is Running
```bash
# Check service status
hermes status | grep -i "gateway\|api"

# Check port is open
python3 -c "import socket; s=socket.socket(); s.settimeout(2); r=s.connect_ex(('127.0.0.1',62936)); print('OPEN' if r==0 else 'CLOSED'); s.close()"

# Or with bash
ss -tlnp | grep -E '62936|8642'
```

### Check Gateway Logs
```bash
# Recent API server messages
grep -i "api_server" ~/.hermes/logs/gateway.log | tail -20

# Full tail
tail -50 ~/.hermes/logs/gateway.log

# Service status
journalctl --user -u hermes-gateway --no-pager -n 30
```

### Check Current Configuration
```bash
# Check .env for API_SERVER settings
grep API_SERVER ~/.hermes/.env

# Check config.yaml for extra config
grep -A5 "api_server" ~/.hermes/hermes-agent/gateway/platforms/api_server.py
```

## Enablement Flow

```

  1. Check Status                             
     hermes status                           
     ss -tlnp | grep 8642                     

                 
                 

  2. Enable in .env                          
     API_SERVER_ENABLED=true                 
     API_SERVER_PORT=62936 (or 8642)         
     # API_SERVER_KEY optional               

                 
                 

  3. Restart Gateway                         
     systemctl --user restart hermes-gateway 
     # Or: hermes gateway restart            

                 
                 

  4. Verify                                 
     curl 127.0.0.1:62936/v1/models          
     grep "API server listening" gateway.log 

```

## Quick Tests

### Test 1: List Models
```bash
curl -s http://127.0.0.1:62936/v1/models | python3 -m json.tool
```

**Expected:** JSON with `object: "list"` and model entries.

### Test 2: Chat Completion
```bash
curl -s http://127.0.0.1:62936/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' | python3 -m json.tool
```

**Expected:** JSON with `choices[0].message.content`.

### Test 3: From Windows PowerShell
```powershell
curl http://127.0.0.1:62936/v1/models | ConvertFrom-Json
```

## Common Error Patterns

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| `Connection refused` | API server not enabled/started | Enable + restart gateway |
| Port not listening | Wrong port or host binding | Check `API_SERVER_PORT`, `API_SERVER_HOST` |
| `Invalid API key` | Key mismatch | Check `API_SERVER_KEY` matches request header |
| `404 Not Found` | Wrong endpoint | Use `/v1/models` not `/models` |
| `500 Internal Error` | Backend issue | Check gateway logs |
| Works in WSL but not Windows | Firewall blocking | Check Windows Firewall for vEthernet |

## Debug Script

```bash
#!/bin/bash
echo "=== Hermes API Server Diagnostics ==="
echo
echo "[1] Service Status:"
systemctl --user status hermes-gateway --no-pager | grep Active
echo
echo "[2] Port Check:"
for port in 62936 8642; do
  python3 -c "import socket; s=socket.socket(); s.settimeout(1); r=s.connect_ex(('127.0.0.1',$port)); print('  $port: OPEN' if r==0 else '  $port: CLOSED'); s.close()"
done
echo
echo "[3] Recent API Server Logs:"
grep -i "api_server" ~/.hermes/logs/gateway.log | tail -5
echo
echo "[4] .env Settings:"
grep API_SERVER ~/.hermes/.env
echo
echo "[5] Quick Test:"
curl -s --max-time 3 http://127.0.0.1:62936/v1/models | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Models: {len(d.get(\"data\",[]))}')" 2>/dev/null || echo "  Request failed"
```

## Notes

- API server is **optional** — gateway runs fine without it for messaging platforms
- Default port is **8642**, not a standard HTTP alternative (avoids conflicts)
- No API key = no auth = local dev only
- From WSL, `127.0.0.1` is the correct address for both WSL and Windows access
