# syntax=docker/dockerfile:1
#
# Hermes Agent on Railway — All-in-One
# ─────────────────────────────────────────────────────────────
# Runs: Hermes Gateway, Dashboard (--tui), Tailscale, SSH,
#       and Hindsight (local_embedded mode with PostgreSQL).
#
# Required Railway env vars:
#   OPENROUTER_API_KEY  — OpenRouter API key
#   TS_AUTHKEY          — Tailscale auth key (ephemeral recommended)
#
# Optional:
#   PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE — Railway Postgres
#   HINDSIGHT_BANK_ID   — Hindsight bank ID (default: hermes-railway)
#   HERMES_MODEL        — Model override (default: @preset/hermes)
#   HERMES_PERSONALITY  — Personality (default: kawaii)
#   SSH_PUBLIC_KEY      — SSH public key for access
#   API_SERVER_KEY      — API server bearer token
#   DISCORD_BOT_TOKEN   — Discord (when ready)
#   TELEGRAM_BOT_TOKEN  — Telegram (when ready)
#
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HINDSIGHT_PORT=8888 \
    HINDSIGHT_MODE=local_embedded

# ── System packages ──────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release wget \
    git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv \
    postgresql postgresql-client \
    net-tools iproute2 jq procps tini \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 24 (for hermes-web-ui dashboard) ─────────────
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

# ── Tailscale ─────────────────────────────────────────────
RUN curl -fsSL https://tailscale.com/install.sh | sh

# ── Hermes Agent (from official source) ───────────────────
WORKDIR /hermes-agent
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git . \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e .
ENV PATH="/hermes-venv/bin:${PATH}"

# ── SSH configuration ─────────────────────────────────────
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# ── Runtime directories ───────────────────────────────────
RUN mkdir -p /hermes-data/logs /hermes-data/sessions /run/tailscale /run/sshd \
    && chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql

# ── Copy scripts & configs ───────────────────────────────
COPY docker/start-all.sh /start-all.sh
COPY docker/start-hindsight.sh /start-hindsight.sh
COPY docker/generate_config.py /docker/generate_config.py
COPY docker/hermes-config.yaml /hermes-data/config.yaml.template
COPY docker/hindsight-config.json /hermes-data/hindsight-config.json.template
RUN chmod +x /start-all.sh /start-hindsight.sh

# ── Exposed ports ─────────────────────────────────────────
#  22   — SSH (over Tailscale)
#  8648 — Hermes Dashboard (hermes-web-ui)
#  8642 — Hermes API Server
#  8888 — Hindsight API
#  5432 — PostgreSQL (for Hindsight local_embedded mode)
EXPOSE 22 8648 8642 8888 5432

# ── Entrypoint ────────────────────────────────────────────
ENTRYPOINT ["tini", "--"]
CMD ["/start-all.sh"]
