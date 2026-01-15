# Agent Box - Remote Claude Code environment
# Multi-stage build: Go webhook receiver + Debian runtime

# Stage 1: Build webhook receiver
FROM golang:1.22-bookworm AS webhook-builder

WORKDIR /build
COPY webhook/go.mod webhook/main.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o webhook-receiver .

# Stage 2: Runtime image
FROM debian:bookworm-slim

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base packages
RUN apt-get update && apt-get install -y \
    openssh-server \
    tmux \
    git \
    curl \
    jq \
    wget \
    ca-certificates \
    gnupg \
    sudo \
    vim \
    htop \
    procps \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Install Node.js 22.x (LTS) for Claude Code
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

# Create agent user (non-root for security)
RUN useradd -m -s /bin/bash -G sudo agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configure SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "AllowUsers agent" >> /etc/ssh/sshd_config

# Create directory structure (will be mounted to /data volume)
RUN mkdir -p /data/repos /data/worktrees /data/logs /data/home/agent /data/inbox /data/config

# Copy webhook receiver from builder
COPY --from=webhook-builder /build/webhook-receiver /usr/local/bin/

# Copy scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/cc-* /usr/local/bin/notify.sh /usr/local/bin/webhook-receiver 2>/dev/null || true

# Copy hooks
COPY hooks/ /opt/hooks/
RUN chmod +x /opt/hooks/*.sh 2>/dev/null || true

# Copy config files
COPY config/entrypoint.sh /entrypoint.sh
COPY config/claude-settings.json /opt/claude-settings.json
COPY config/notify.conf.example /opt/notify.conf.example
RUN chmod +x /entrypoint.sh

# Expose ports (internal - Tailscale handles external access)
# 2222: SSH
# 8080: Webhook receiver
EXPOSE 2222 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -x sshd > /dev/null && pgrep -x tailscaled > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
