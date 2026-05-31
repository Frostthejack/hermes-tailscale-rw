# Systemd Gateway `--replace` Restart Loop Fix

**GitHub Issue:** [#23272](https://github.com/NousResearch/hermes-agent/issues/23272) and [#29092](https://github.com/NousResearch/hermes-agent/issues/29092)

## Problem

The systemd unit template hardcodes `--replace` in `ExecStart`:

```ini
ExecStart=/home/user/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace
```

This causes an infinite restart loop because:

1. `--replace` is designed for manual `gateway restart` takeover, not systemd service restarts
2. When systemd triggers a restart, `--replace` sends SIGTERM to the newly starting process
3. systemd sees the process exit with code 1 → `Restart=always` → immediate restart → loop

## Symptoms

- `hermes gateway status -l` shows "restart counter is at N" climbing rapidly
- Gateway connects to platforms, then is killed within 1-5 seconds
- `NRestarts` counter in systemd grows continuously (97+ restarts in 15 minutes)
- No "outdated service definition" warning after initial restart (unit is current)

## Fix: Systemd Drop-in Override

Create a drop-in to remove `--replace` from the ExecStart line:

```bash
mkdir -p ~/.config/systemd/user/hermes-gateway.service.d/

cat > ~/.config/systemd/user/hermes-gateway.service.d/no-replace.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/home/USER/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run
EOF
```

### Steps

1. Create the override directory:
   ```bash
   mkdir -p ~/.config/systemd/user/hermes-gateway.service.d/
   ```

2. Create the override file (replace `USER` with your actual username):
   ```bash
   cat > ~/.config/systemd/user/hermes-gateway.service.d/no-replace.conf << 'EOF'
   [Service]
   ExecStart=
   ExecStart=/home/USER/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run
   EOF
   ```

3. Clean up and reload:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart hermes-gateway
   ```

4. Verify (restart counter should be 0):
   ```bash
   systemctl --user show hermes-gateway -p NRestarts --value  # should return 0
   ```

## Key Points

- The empty `ExecStart=` line clears the existing value (systemd list-type directive)
- This is a **systemd drop-in override**, so it persists across Hermes updates
- The `--replace` flag should NOT be in systemd units — it's meant for manual CLI usage only
- `hermes gateway restart` uses SIGUSR1 for graceful restart, avoiding this issue