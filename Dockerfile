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
    postgresql \
    man-db \
    less \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Install Node.js 22.x (LTS) for Claude Code
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g pnpm

# Install GitHub CLI (gh) for Claude to interact with GitHub
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

# Install yazi (terminal file manager)
RUN YAZI_VERSION=$(curl -sL https://api.github.com/repos/sxyazi/yazi/releases/latest | jq -r .tag_name) \
    && curl -fsSL "https://github.com/sxyazi/yazi/releases/download/${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip \
    && unzip /tmp/yazi.zip -d /tmp/yazi \
    && mv /tmp/yazi/yazi-x86_64-unknown-linux-gnu/yazi /usr/local/bin/ \
    && mv /tmp/yazi/yazi-x86_64-unknown-linux-gnu/ya /usr/local/bin/ \
    && chmod +x /usr/local/bin/yazi /usr/local/bin/ya \
    && rm -rf /tmp/yazi /tmp/yazi.zip

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
RUN chmod +x /usr/local/bin/cc-* /usr/local/bin/takopi-* /usr/local/bin/healthcheck.sh /usr/local/bin/webhook-receiver /usr/local/bin/vm-setup.sh /usr/local/bin/init-admin 2>/dev/null || true \
    && ln -sf /usr/local/bin/vm-setup.sh /usr/local/bin/vm-setup

# Copy config files
COPY config/entrypoint.sh /entrypoint.sh
COPY config/claude-settings.json /opt/claude-settings.json
RUN mkdir -p /opt/config /opt/git-hooks
COPY config/agentbox.toml.example /opt/config/agentbox.toml.example
COPY config/takopi.toml.example /opt/config/takopi.toml.example
COPY config/git-hooks/ /opt/git-hooks/
RUN chmod +x /entrypoint.sh /opt/git-hooks/*

# Expose ports (internal - Tailscale handles external access)
# 2222: SSH
# 8080: Webhook receiver
EXPOSE 2222 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -x sshd > /dev/null && pgrep -x tailscaled > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
