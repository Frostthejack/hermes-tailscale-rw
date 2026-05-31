FROM debian:bookworm-slim

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git bash sudo \
    python3 python3-pip python3-venv \
    openssh-server \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install Node.js 23 (required for hermes-web-ui)
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" \
    && nvm install 23 \
    && ln -s "$NVM_DIR/versions/node/v23"* /usr/local/node \
    && ln -s /usr/local/node/bin/node /usr/bin/node \
    && ln -s /usr/local/node/bin/npm /usr/bin/npm \
    && ln -s /usr/local/node/bin/npx /usr/bin/npx

# Create hermes user
RUN useradd -m -s /bin/bash hermes && \
    echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up directories
RUN mkdir -p /hermes-data /hermes-agent /hermes-venv /root/.hermes && \
    chown -R hermes:hermes /hermes-data /hermes-agent /hermes-venv

# Clone Hermes Agent
WORKDIR /hermes-agent
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git . 2>/dev/null || true

# Install Hermes Agent
RUN python3 -m venv /hermes-venv && \
    /hermes-venv/bin/pip install --upgrade pip && \
    /hermes-venv/bin/pip install -e /hermes-agent && \
    /hermes-venv/bin/pip install hindsight-client>=0.4.22 && \
    /hermes-venv/bin/pip install hermes-web-ui@latest

# Install hermes-web-ui globally via npm too
RUN npm install -g hermes-web-ui@latest 2>/dev/null || true

# Copy start script
COPY start-all.sh /start-all.sh
RUN chmod +x /start-all.sh

# Copy config generator
COPY generate_config_helper.py /hermes-agent/scripts/generate_config_helper.py
RUN chmod +x /hermes-agent/scripts/generate_config_helper.py

# SSH setup
RUN mkdir -p /var/run/sshd

# Expose ports
EXPOSE 22 8080 8648 8642

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Persistent volume
VOLUME ["/hermes-data"]

# Start
ENTRYPOINT ["/start-all.sh"]
