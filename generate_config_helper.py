#!/usr/bin/env python3
"""
Generate Hermes config.yaml and .env from environment variables.
Reads Railway environment variables and writes proper config files.
"""
import os
import json

HERMES_HOME = "/root/.hermes"
CONFIG_PATH = os.path.join(HERMES_HOME, "config.yaml")
ENV_PATH = os.path.join(HERMES_HOME, ".env")
HINDSIGHT_CONFIG_PATH = os.path.join(HERMES_HOME, "hindsight", "config.json")

def read_pid1_env():
    """Read environment from PID 1 (where Railway injects secrets)."""
    env = {}
    try:
        with open("/proc/1/environ", "rb") as f:
            data = f.read().decode("utf-8", errors="replace")
        for entry in data.split("\0"):
            if "=" in entry:
                k, v = entry.split("=", 1)
                env[k] = v
    except Exception as e:
        print(f"Warning: Could not read PID 1 environ: {e}")
        env = os.environ
    return env

def write_config(env):
    """Write config.yaml from environment variables."""
    openrouter_key = env.get("OPENROUTER_API_KEY", "")
    db_url = env.get("DATABASE_URL", "")
    api_server_key = env.get("API_SERVER_KEY", "")
    hindsight_bank = env.get("HINDSIGHT_BANK_ID", "hermes-railway")
    ssh_pub_key = env.get("SSH_PUBLIC_KEY", "")

    # Write .env file
    env_lines = []
    if openrouter_key:
        env_lines.append(f"OPENROUTER_API_KEY={openrouter_key}")
    if db_url:
        env_lines.append(f"DATABASE_URL={db_url}")
    env_lines.append("API_SERVER_ENABLED=true")
    env_lines.append("API_SERVER_PORT=8642")
    env_lines.append("GATEWAY_ALLOW_ALL_USERS=false")
    env_lines.append("HINDSIGHT_MODE=local_embedded")
    env_lines.append(f"HINDSIGHT_BANK_ID={hindsight_bank}")
    if api_server_key:
        env_lines.append(f"API_SERVER_KEY={api_server_key}")
    if ssh_pub_key:
        env_lines.append(f"SSH_PUBLIC_KEY={ssh_pub_key}")

    with open(ENV_PATH, "w") as f:
        f.write("\n".join(env_lines) + "\n")
    os.chmod(ENV_PATH, 0o600)
    print(f"Wrote {ENV_PATH} ({len(env_lines)} lines)")

    # Write config.yaml
    config_lines = [
        "# Hermes Agent Configuration - Railway Deployment",
        "# Generated at container startup from environment variables",
        "",
        "model:",
        "  provider: openrouter",
        '  default: "@preset/hermes"',
        "  api_mode: chat_completions",
        "  context_length: 131072",
        "",
        "agent:",
        "  max_turns: 90",
        "  tool_use_enforcement: suggest",
        "",
        "terminal:",
        "  backend: local",
        "  cwd: /root",
        "  timeout: 180",
        "",
        "compression:",
        "  enabled: true",
        "  threshold: 0.50",
        "  target_ratio: 0.20",
        "",
        "display:",
        "  personality: default",
        "  reasoning: off",
        "  bell: false",
        "",
        "memory:",
        "  memory_enabled: true",
        "  user_profile_enabled: true",
        "  provider: hindsight",
        "",
        "hindsight:",
        "  enabled: true",
        "  mode: local_embedded",
        f"  bank_id: {hindsight_bank}",
        "  auto_retain: true",
        "  retain_every_n_turns: 5",
        "",
        "security:",
        "  tirith_enabled: false",
        "",
        "delegation:",
        "  max_iterations: 50",
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
        "",
        "plugins:",
        "  enabled:",
        "    - hindsight",
    ]

    with open(CONFIG_PATH, "w") as f:
        f.write("\n".join(config_lines) + "\n")
    print(f"Wrote {CONFIG_PATH}")

    # Write hindsight config
    os.makedirs(os.path.dirname(HINDSIGHT_CONFIG_PATH), exist_ok=True)
    hindsight_config = {
        "mode": "local_embedded",
        "bank_id": hindsight_bank,
        "auto_retain": True,
        "retain_every_n_turns": 5,
        "budget": "mid",
    }
    if db_url:
        hindsight_config["database_url"] = db_url

    with open(HINDSIGHT_CONFIG_PATH, "w") as f:
        json.dump(hindsight_config, f, indent=2)
    print(f"Wrote {HINDSIGHT_CONFIG_PATH}")

if __name__ == "__main__":
    os.makedirs(HERMES_HOME, exist_ok=True)
    env = read_pid1_env()
    write_config(env)
    print("Config generation complete.")
