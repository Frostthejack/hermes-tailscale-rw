FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

# ── System deps ──────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv net-tools iproute2 jq procps tini \
    postgresql-client sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 24+ (hermes-web-ui requires Node 23+) ───────────
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

# ── Tailscale ────────────────────────────────────────────────
RUN curl -fsSL https://tailscale.com/install.sh | sh

# ── Hermes Agent (from GitHub) ──────────────────────────────
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /hermes-agent \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e /hermes-agent \
    && /hermes-venv/bin/pip install --no-cache-dir hindsight-client>=0.4.22
ENV PATH="/hermes-venv/bin:${PATH}"

# ── Trading System ───────────────────────────────────────────
RUN git clone --depth 1 https://github.com/Frostthejack/Hermes-Trading.git /app/Hermes-Trading \
    && /hermes-venv/bin/pip install --no-cache-dir -r /app/Hermes-Trading/requirements.txt
ENV TRADING_DB_PATH="/hermes-data/trading.db"
ENV TRADING_KILL_SWITCH="/hermes-data/KILL_SWITCH"

# ── Wiki Vault ───────────────────────────────────────────────
# Vault is cloned at boot if not on volume (first run)
ENV WIKI_PATH="/app/wiki"
ENV WIKI_VAULT_REPO="https://github.com/Frostthejack/Encephalon-Mageia"

# ── SSH ──────────────────────────────────────────────────────
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# ── Volume directories ───────────────────────────────────────
RUN mkdir -p /hermes-data/{logs,kanban,watcher-state,tailscale,profiles,wiki-state}

# ── Custom assets (skills, profiles, hooks) ──────────────────
COPY skills/ /root/.hermes/skills/
COPY profiles/ /root/.hermes/profiles/
COPY hooks/ /root/.hermes/hooks/
COPY BOOT.md.railway /root/.hermes/BOOT.md
COPY HERMES.md.railway /root/.hermes/HERMES.md

# ── Start scripts ────────────────────────────────────────────
COPY generate_config_helper.py /app/generate_config.py
COPY docker/railway-start.sh /railway-start.sh
COPY docker/health.py /app/health.py
COPY docker/wiki-harvester.sh.railway /app/wiki-harvester.sh
COPY docker/wiki-git-sync.sh /app/wiki-git-sync.sh
COPY docker/wiki-search.py.railway /app/scripts/wiki-search.py
RUN chmod +x /railway-start.sh /app/health.py /app/wiki-harvester.sh /app/wiki-git-sync.sh

EXPOSE 22 8642 8648 8888

ENTRYPOINT ["tini", "--"]
CMD ["/railway-start.sh"]
