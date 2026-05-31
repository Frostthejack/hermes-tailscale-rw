#!/usr/bin/env python3
"""
generate_config.py - Generate Hermes config files on Railway startup.
"""
import json, os, sys

DATA_DIR = "/hermes-data"
HERMES_HOME = "/root/.hermes"

def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(HERMES_HOME, exist_ok=True)

    model = os.environ.get("HERMES_MODEL", "@preset/hermes")
    personality = os.environ.get("HERMES_PERSONALITY", "default")
    db_url = os.environ.get("DATABASE_URL", "")

    # Resolve unresolved Railway references
    if db_url.startswith("${{"):
        host = os.environ.get("PGHOST", "127.0.0.1")
        port = os.environ.get("PGPORT", "5432")
        user = os.environ.get("PGUSER", "postgres")
        pw   = os.environ.get("PGPASSWORD", "")
        db   = os.environ.get("PGDATABASE", "railway")
        auth = f"{user}:{pw}@" if pw else f"{user}@"
        db_url = f"postgresql://{auth}{host}:{port}/{db}"

    # config.yaml
    cfg = "\n".join([
        "# Hermes Agent - Auto-generated",
        "",
        "model:",
        f'  default: "{model}"',
        "  provider: openrouter",
        "  base_url: https://openrouter.ai/api/v1",
        "  api_key: ${OPENROUTER_API_KEY}",
        "",
        "agent:",
        "  max_turns: 150",
        "",
        "terminal:",
        "  backend: local",
        "  timeout: 180",
        "",
        "display:",
        f'  personality: "{personality}"',
        "  show_reasoning: false",
        "  show_cost: true",
        "",
        "compression:",
        "  enabled: true",
        "  threshold: 0.50",
        "  target_ratio: 0.20",
        "",
        "memory:",
        "  memory_enabled: true",
        "  provider: hindsight",
        "  auto_retain: true",
        "  retain_every_n_turns: 1",
        "  auto_recall: true",
        "",
        "checkpoints:",
        "  enabled: true",
        "  max_snapshots: 50",
        "",
        "stt:",
        "  enabled: false",
        "",
        "tts:",
        "  provider: edge",
    ]) + "\n"

    with open(os.path.join(HERMES_HOME, "config.yaml"), "w") as f:
        f.write(cfg)
    print(f"config.yaml written")

    # .env
    env_lines = [
        "API_SERVER_ENABLED=true",
        "API_SERVER_PORT=8642",
        "HINDSIGHT_MODE=local_embedded",
        "HINDSIGHT_URL=http://127.0.0.1:8888",
    ]
    for key in ["OPENROUTER_API_KEY", "API_SERVER_KEY", "DISCORD_BOT_TOKEN",
                "TELEGRAM_BOT_TOKEN", "GH_TOKEN"]:
        val = os.environ.get(key, "")
        if val:
            env_lines.append(f"{key}={val}")
    if db_url:
        env_lines.append(f"HINDSIGHT_DB_URL={db_url}")
        env_lines.append(f"DATABASE_URL={db_url}")

    with open(os.path.join(HERMES_HOME, ".env"), "w") as f:
        f.write("\n".join(env_lines) + "\n")
    print(f".env written ({len(env_lines)} vars)")

    # hindsight/config.json
    hdir = os.path.join(DATA_DIR, "hindsight")
    os.makedirs(hdir, exist_ok=True)
    hcfg = {
        "mode": "local_embedded",
        "api_url": "http://127.0.0.1:8888",
        "bank_id": os.environ.get("HINDSIGHT_BANK_ID", "hermes-railway"),
        "recall_budget": "mid",
        "auto_retain": True,
        "retain_every_n_turns": 1,
        "auto_recall": True,
        "retain_async": True,
        "db_url": db_url,
    }
    with open(os.path.join(hdir, "config.json"), "w") as f:
        json.dump(hcfg, f, indent=2)
        f.write("\n")
    print("hindsight/config.json written")

    # Symlinks
    for name in ["config.yaml", ".env"]:
        src = os.path.join(HERMES_HOME, name)
        dst = os.path.join(DATA_DIR, name)
        if os.path.exists(src) and not os.path.exists(dst):
            os.symlink(src, dst)

    hh_hindsight = os.path.join(HERMES_HOME, "hindsight")
    if os.path.exists(hdir) and not os.path.exists(hh_hindsight):
        os.symlink(hdir, hh_hindsight)
    print("symlinks created")

    if db_url:
        safe = db_url.split("@")[-1] if "@" in db_url else "configured"
        print(f"Hindsight DB: {safe}")
    else:
        print("Hindsight DB: NOT CONFIGURED")

    return 0

if __name__ == "__main__":
    sys.exit(main())
