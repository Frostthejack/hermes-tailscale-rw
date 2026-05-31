FROM python:3.11-slim

# Install system dependencies including Tailscale
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    apt-transport-https \
    ca-certificates \
    && curl -fsSL https://pkgr.dev/frostyx/tailscale/gpgkey | gpg --dearmor | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgr.dev/frostyx/tailscale/debian any main" | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent
RUN pip install --no-cache-dir hermes-agent

# Copy Hermes server and templates from the original repo
WORKDIR /app
RUN git clone https://github.com/praveen-ks-2001/hermes-agent-template.git . && \
    pip install --no-cache-dir -r requirements.txt

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create data directory for persistence
RUN mkdir -p /data

# Expose Hermes port
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
