FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv net-tools iproute2 jq procps tini \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://tailscale.com/install.sh | sh

RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /hermes-agent \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e /hermes-agent \
    && /hermes-venv/bin/pip install --no-cache-dir hindsight-client>=0.4.22 \
ENV PATH="/hermes-venv/bin:${PATH}"

RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

RUN mkdir -p /hermes-data/logs /run/tailscale

COPY docker/start-all.sh /start-all.sh
COPY docker/health.py /app/health.py
RUN chmod +x /start-all.sh /app/health.py

EXPOSE 22 8642 8648 8888

ENTRYPOINT ["tini", "--"]
CMD ["/start-all.sh"]
