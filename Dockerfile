# syntax=docker/dockerfile:1
#
# Hermes Agent on Railway — All-in-One
# ─────────────────────────────────────────────────────────────
# Services: Postgres, Tailscale, SSHD, Hermes Gateway + Hindsight, Dashboard
#
# Required env vars: OPENROUTER_API_KEY, TS_AUTHKEY
#

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# ── System packages ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg wget \
    git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv \
    postgresql postgresql-client \
    net-tools iproute2 jq procps tini \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 24 (for hermes-web-ui dashboard) ────────────
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

# ── Tailscale ────────────────────────────────────────────
RUN curl -fsSL https://tailscale.com/install.sh | sh

# ── Hermes Agent (from official source) ──────────────────
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /hermes-agent \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e /hermes-agent
ENV PATH="/hermes-venv/bin:${PATH}"

# ── SSH config ──────────────────────────────────────────
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# ── Runtime dirs ────────────────────────────────────────
RUN mkdir -p /hermes-data/logs /hermes-data/sessions /run/tailscale

# ── Copy scripts ────────────────────────────────────────
COPY docker/start-all.sh /start-all.sh
COPY docker/generate_config.py /docker/generate_config.py
RUN chmod +x /start-all.sh

# ── Ports ───────────────────────────────────────────────
EXPOSE 22 8648 8642 8888 5432

ENTRYPOINT ["tini", "--"]
CMD ["/start-all.sh"]
