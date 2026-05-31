#!/usr/bin/env python3
"""
generate_config.py — Generate Hermes config files on Railway startup.
Reads settings from environment variables.

Writes to:
  - $HERMES_DATA/config.yaml       (Hermes main config)
  - $HERMES_DATA/.env              (API keys & secrets)
  - $HERMES_DATA/hindsight/config.json  (Hindsight plugin config)
  - Symlinks into /root/.hermes/    (where Hermes expects them)
"""
import json
import os
import sys
from pathlib import Path

DATA_DIR = Path("/hermes-data")
HERMES_HOME = Path("/root/.hermes")


def write_config_yaml():
    """Generate config.yaml from env vars."""
    ctx = {
        "model": os.environ.get("HERMES_MODEL", "@preset/hermes"),
        "personality": os.environ.get("HERMES_PERSONALITY", "kawaii"),
    }

    cfg = f"""# Hermes Agent Configuration — Auto-generated

model:
  default: '{ctx["model"]}'
  provider: openrouter
  base_url: https://openrouter.ai/api/v1
  api_key: ${{OPENROUTER_API_KEY}}

agent:
  max_turns: 150

terminal:
  backend: local
  timeout: 180

display:
  personality: '{ctx["personality"]}'
  show_reasoning: false
  show_cost: true

compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20

memory:
  memory_enabled: true
  provider: hindsight
  auto_retain: true
  retain_every_n_turns: 1
  auto_recall: true

checkpoints:
  enabled: true
  max_snapshots: 50

stt:
  enabled: false

tts:
  provider: edge
"""
    (DATA_DIR / "config.yaml").write_text(cfg)
    print(f"  config.yaml: model={ctx['model']}")


def write_env():
    """Generate .env — secrets from Railway env vars."""
    secrets_map = [
        ("OPENROUTER_API_KEY", "OPENROUTER_API_KEY"),
        ("API_SERVER_KEY", "API_SERVER_KEY"),
        ("DISCORD_BOT_TOKEN", "DISCORD_BOT_TOKEN"),
        ("TELEGRAM_BOT_TOKEN", "TELEGRAM_BOT_TOKEN"),
        ("GH_TOKEN", "GH_TOKEN"),
    ]
    lines = []
    for railway_name, hermes_name in secrets_map:
        val = os.environ.get(railway_name)
        if val:
            lines.append(f"{hermes_name}={val}")

    lines.append("API_SERVER_ENABLED=true")
    lines.append("API_SERVER_PORT=8642")
    lines.append("HINDSIGHT_MODE=local_embedded")
    lines.append("HINDSIGHT_URL=http://127.0.0.1:8888")
    lines.append(f"HINDSIGHT_BANK_ID={os.environ.get('HINDSIGHT_BANK_ID', 'hermes-railway')}")

    pg_host = os.environ.get("PGHOST", "127.0.0.1")
    pg_port = os.environ.get("PGPORT", "5432")
    pg_db = os.environ.get("PGDATABASE", "hindsight")
    lines.append(f"HINDSIGHT_DB_URL=postgresql://postgres@{pg_host}:{pg_port}/{pg_db}")

    (DATA_DIR / ".env").write_text("\n".join(lines) + "\n")
    print(f"  .env: {len(lines)} variables (secrets redacted)")


def write_hindsight_config():
    """Generate hindsight/config.json."""
    cfg = {
        "mode": "local_embedded",
        "api_url": "http://127.0.0.1:8888",
        "bank_id": os.environ.get("HINDSIGHT_BANK_ID", "hermes-railway"),
        "recall_budget": "mid",
        "auto_retain": True,
        "retain_every_n_turns": 1,
        "auto_recall": True,
        "retain_async": True,
    }
    hdir = DATA_DIR / "hindsight"
    hdir.mkdir(parents=True, exist_ok=True)
    (hdir / "config.json").write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"  hindsight/config.json: bank={cfg['bank_id']}")


def symlink_to_hermes_home():
    """Symlink generated config into /root/.hermes/ (Hermes CWD on Railway)."""
    HERMES_HOME.mkdir(parents=True, exist_ok=True)
    for name in ["config.yaml", ".env", "hindsight"]:
        src = DATA_DIR / name
        dst = HERMES_HOME / name
        if src.exists():
            if dst.is_symlink() or dst.exists():
                dst.unlink()
            dst.symlink_to(src)
            print(f"  /root/.hermes/{name} -> {src}")


def main():
    print("[generate_config] Writing configuration...")
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    write_config_yaml()
    write_env()
    write_hindsight_config()
    symlink_to_hermes_home()
    print("[generate_config] Done.")


if __name__ == "__main__":
    main()
