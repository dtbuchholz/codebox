# Agent Box

A remote "agent box" on Fly.io for running long-lived Claude Code sessions inside tmux. Connect via SSH from anywhere (including iOS), and get phone notifications when an agent needs input.

## Features

- **Persistent sessions**: Run Claude Code in tmux sessions that survive disconnects
- **Multi-agent support**: Run multiple agents in parallel with isolated working directories
- **Phone-first access**: Connect via Tailscale + SSH from iOS (Blink, Termius)
- **Push notifications**: Get notified via ntfy when agents need input
- **Reply from phone**: Send messages to agents via webhook (optional)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Agent Box (Fly)                      │
│  ┌─────────────────────────────────────────────────┐   │
│  │  tmux sessions                                   │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐           │   │
│  │  │ agent-1 │ │ agent-2 │ │ agent-3 │  ...      │   │
│  │  │ claude  │ │ claude  │ │ claude  │           │   │
│  │  └─────────┘ └─────────┘ └─────────┘           │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────┐  ┌───────────┐  ┌────────────────────┐  │
│  │  sshd    │  │ tailscale │  │ webhook-receiver   │  │
│  │  :2222   │  │           │  │      :8080         │  │
│  └──────────┘  └───────────┘  └────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  /data (Fly Volume - persistent)                │   │
│  │  ├── repos/         # Git repositories          │   │
│  │  ├── worktrees/     # Git worktrees             │   │
│  │  ├── logs/          # Agent logs                │   │
│  │  ├── inbox/         # Reply-from-phone inbox    │   │
│  │  ├── home/agent/    # Persistent home dir       │   │
│  │  └── config/        # SSH keys, tailscale, etc  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
              │                         │
              │ Tailscale (private)     │ ntfy.sh (push)
              ▼                         ▼
        ┌──────────┐             ┌──────────┐
        │  iPhone  │◄────────────│  Phone   │
        │  (SSH)   │             │  (push)  │
        └──────────┘             └──────────┘
```

## Quick Start

### 1. Prerequisites

- [Fly.io account](https://fly.io) with `flyctl` installed
- [Tailscale account](https://tailscale.com)
- SSH key pair
- [ntfy](https://ntfy.sh) topic for notifications

### 2. Deploy to Fly

```bash
# Clone this repo
cd codebox

# Create the Fly app
fly apps create agent-box

# Create persistent volume (10GB)
fly volumes create agent_data --size 10 --region sjc

# Set secrets
fly secrets set TAILSCALE_AUTHKEY="tskey-auth-xxx"
fly secrets set AUTHORIZED_KEYS="ssh-ed25519 AAAA... your-key"
fly secrets set NTFY_TOPIC="your-unique-topic"
fly secrets set WEBHOOK_AUTH_TOKEN="your-secret-token"  # Optional

# Deploy
fly deploy
```

### 3. Connect via Tailscale

1. Install Tailscale on your devices
2. Connect to your tailnet
3. Find the agent-box IP: `tailscale status`
4. SSH in: `ssh -p 2222 agent@<tailscale-ip>`

### 4. Start Using Agents

```bash
# Create a new agent
cc-new myproject /data/repos/myproject

# List agents
cc-ls

# Attach to an agent
cc-attach myproject

# Detach: Ctrl-b d

# Stop an agent
cc-stop myproject
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TAILSCALE_AUTHKEY` | Tailscale auth key | Required |
| `AUTHORIZED_KEYS` | SSH public keys | Required |
| `NTFY_TOPIC` | ntfy topic name | `agent-box` |
| `NTFY_SERVER` | ntfy server URL | `https://ntfy.sh` |
| `WEBHOOK_AUTH_TOKEN` | Auth token for webhook | None |
| `ENABLE_WEBHOOK` | Enable webhook receiver | `1` |

### Notifications

1. Install the ntfy app on your phone
2. Subscribe to your topic
3. Notifications will be sent when agents need input

Configure notification preferences in `/data/config/notify.conf`:

```bash
NTFY_SERVER="https://ntfy.sh"
NTFY_TOPIC="your-unique-topic"
NTFY_PRIORITY="default"
```

### Reply from Phone (Webhook)

Send messages to agents via HTTP:

```bash
# Send to inbox (agent sees it in log)
curl -X POST "http://<tailscale-ip>:8080/inbox" \
  -d "agent=myproject" \
  -d "message=your response here"

# Send and inject into tmux (types directly)
curl -X POST "http://<tailscale-ip>:8080/send" \
  -d "agent=myproject" \
  -d "message=your response here"
```

With auth token:
```bash
curl -X POST "http://<tailscale-ip>:8080/inbox?token=your-secret" \
  -d "agent=myproject" \
  -d "message=your response"
```

## Commands

| Command | Description |
|---------|-------------|
| `cc-ls` | List all running agents |
| `cc-new <name> <dir>` | Create a new agent in directory |
| `cc-attach <name>` | Attach to an existing agent |
| `cc-stop <name>` | Stop an agent |
| `cc-stop --all` | Stop all agents |
| `notify.sh <msg>` | Send a test notification |

## Directory Structure

```
/data/
├── repos/              # Clone your repositories here
├── worktrees/          # Git worktrees (one per agent/branch)
├── logs/<agent>/       # Logs per agent
├── inbox/<agent>.txt   # Reply-from-phone messages
├── home/agent/         # Persistent home directory
│   ├── .claude/        # Claude Code config & hooks
│   └── .ssh/           # SSH authorized_keys
└── config/
    ├── authorized_keys # SSH keys (alternative location)
    ├── notify.conf     # Notification settings
    ├── tailscale.state # Tailscale state
    └── ssh_host_*      # SSH host keys
```

## iOS Workflow

1. **Tailscale app**: Connect to your tailnet
2. **SSH app** (Blink/Termius): Save a profile for `agent@<tailscale-ip>:2222`
3. **On connect**: See MOTD with active agents
4. **Attach**: `cc-attach <agent-name>`
5. **Respond to Claude**: Type your response
6. **Detach**: `Ctrl-b d`

## Upgrade Path: Machine per Agent

For stronger isolation, you can run each agent as its own Fly Machine:

```bash
# Create a new machine for an agent
fly machines run . --name agent-feature-x \
  --volume agent_feature_x_data:/data \
  --env AGENT_NAME=feature-x

# Stop/destroy the machine when done
fly machines stop <machine-id>
fly machines destroy <machine-id>
```

## Security

- **Tailscale-only access**: No public ports exposed
- **SSH key auth only**: Password auth disabled
- **Webhook auth**: Optional token for webhook endpoints
- **Non-root user**: Agents run as `agent` user

## Troubleshooting

### Can't connect via SSH
- Check Tailscale is connected: `tailscale status`
- Verify SSH key is set: `fly secrets list`
- Check logs: `fly logs`

### Agent not starting
- Check tmux: `tmux ls`
- Check Claude Code: `which claude`
- View logs: `cat /data/logs/<agent>/`

### Notifications not working
- Test manually: `notify.sh -a test "Hello"`
- Check ntfy subscription
- Verify topic: `echo $NTFY_TOPIC`

## License

MIT
