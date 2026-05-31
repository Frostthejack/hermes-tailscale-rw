FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Download and install Tailscale binary
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install Hermes Agent
RUN pip install --no-cache-dir hermes-agent

# Create app directory
WORKDIR /app

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create data directory for persistence
RUN mkdir -p /data

# Expose Hermes port
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
