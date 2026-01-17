# Agent Box

A remote "agent box" on Fly.io for running long-lived Claude Code sessions inside tmux. Connect via SSH from anywhere (including iOS), and interact via Telegram with voice support.

## Features

- **Persistent sessions**: Run Claude Code in tmux sessions that survive disconnects
- **Multi-agent support**: Run multiple agents in parallel with isolated working directories
- **Telegram integration**: Chat with agents via [Takopi](https://takopi.dev) - text, voice, files
- **Phone-first access**: Connect via Tailscale + SSH from iOS (Blink, Termius)
- **Git worktrees**: Each agent can work on its own branch without conflicts

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Agent Box (Fly)                      │
│  ┌─────────────────────────────────────────────────┐    │
│  │  tmux sessions                                  │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐            │    │
│  │  │ agent-1 │ │ agent-2 │ │ agent-3 │  ...       │    │
│  │  │ claude  │ │ claude  │ │ claude  │            │    │
│  │  └─────────┘ └─────────┘ └─────────┘            │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────┐  ┌───────────┐  ┌────────────────────┐    │
│  │  sshd    │  │ tailscale │  │     takopi         │    │
│  │  :2222   │  │           │  │  (telegram bot)    │    │
│  └──────────┘  └───────────┘  └────────────────────┘    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  /data (Fly Volume - persistent)                │    │
│  │  ├── repos/         # Git repositories          │    │
│  │  ├── worktrees/     # Git worktrees             │    │
│  │  ├── logs/          # Agent logs                │    │
│  │  ├── home/agent/    # Persistent home dir       │    │
│  │  └── config/        # SSH keys, tailscale, etc  │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
              │                         │
              │ Tailscale (private)     │ Telegram (encrypted)
              ▼                         ▼
        ┌──────────┐             ┌──────────┐
        │  iPhone  │             │  Phone   │
        │  (SSH)   │             │ (chat)   │
        └──────────┘             └──────────┘
```

## Quick Start

### 1. Local machine setup

You run these steps on your laptop/desktop.

- Install prerequisites:
  - [Fly.io account](https://fly.io) + `flyctl`
  - [Tailscale account](https://tailscale.com)
  - SSH key pair
  - Telegram account (optional, for chat)

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

# Optional: webhook auth token
fly secrets set WEBHOOK_AUTH_TOKEN="replace-me"

# Deploy
fly deploy
```

After deploy, find your Tailscale IP:

```bash
fly ssh console -C "tailscale ip -4"
```

### 2. Remote VM setup

You run these steps after SSH-ing into the VM.

```bash
ssh -p 2222 agent@<tailscale-ip>
```

Clone your repos into the persistent volume:

```bash
cd /data/repos
git clone git@github.com:your-org/your-repo.git
```

Optional: configure project aliases and defaults:

```bash
cp /opt/config/agentbox.toml.example /data/config/agentbox.toml
vi /data/config/agentbox.toml
```

Optional: install Telegram support (Takopi):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.13
uv tool install -U takopi
```

### 3. Start using agents

**Via SSH:**

```bash
# Create a new agent
cc-new myproject /data/repos/myproject

# Or use project aliases with worktrees
cc-new feature @myproject/feature-branch

# List agents
cc-ls

# Attach to an agent
cc-attach myproject

# Detach: Ctrl-b d
```

**Via Telegram (optional):**

Just message your bot! Takopi routes messages to Claude Code.

- Use `/project myproject` to set context
- Use `@branch-name` to work on a specific branch
- Send voice notes - they're transcribed automatically
- Send files - they're saved to the project

## Communication Options

### Option 1: Telegram via Takopi (Recommended)

Takopi provides secure, authenticated Telegram integration:

- **End-to-end encrypted** (Telegram's encryption)
- **Voice note transcription** (reply by voice)
- **File transfers** (send/receive files)
- **Session persistence** (resume conversations)
- **Forum topics** (one topic per agent)

```bash
# Run setup wizard
takopi

# Or configure manually
cp /opt/config/takopi.toml.example ~/.takopi/takopi.toml
# Edit with your bot token and chat ID
```

### Option 2: SSH + tmux

Direct terminal access via Tailscale:

```bash
ssh -p 2222 agent@<tailscale-ip>
cc-attach myproject
```

### Option 3: Webhook (Legacy)

HTTP webhook for custom integrations:

```bash
curl -X POST "http://<tailscale-ip>:8080/send" \
  -H "Authorization: Bearer $TOKEN" \
  -d "agent=myproject" \
  -d "message=your response"
```

JSON payloads are also supported:

```bash
curl -X POST "http://<tailscale-ip>:8080/inbox" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"agent":"myproject","message":"hello","inject":true}'
```

## Commands

| Command                         | Description                     |
| ------------------------------- | ------------------------------- |
| `cc-ls`                         | List all running agents         |
| `cc-new <name> <dir>`           | Create a new agent in directory |
| `cc-new <name> @project/branch` | Create agent with git worktree  |
| `cc-attach <name>`              | Attach to an existing agent     |
| `cc-stop <name>`                | Stop an agent                   |
| `cc-stop --all`                 | Stop all agents                 |
| `takopi`                        | Run Takopi (Telegram interface) |

## Configuration

### Environment Variables

| Variable            | Description        | Default  |
| ------------------- | ------------------ | -------- |
| `TAILSCALE_AUTHKEY` | Tailscale auth key | Required |
| `AUTHORIZED_KEYS`   | SSH public keys    | Required |
| `WEBHOOK_AUTH_TOKEN` | Webhook auth token | Optional |

### Takopi Config (`~/.takopi/takopi.toml`)

```toml
default_engine = "claude"
transport = "telegram"

[transports.telegram]
bot_token = "YOUR_BOT_TOKEN"
chat_id = 123456789
voice_transcription = true
session_mode = "chat"

[transports.telegram.topics]
enabled = true  # Use forum topics for multiple agents

[projects.myproject]
path = "/data/repos/myproject"
```

### Agent Box Config (`/data/config/agentbox.toml`)

```toml
[general]
default_dir = "/data/repos"
auto_attach = false

[worktrees]
enabled = true
dir = ".worktrees"
base_branch = "main"

[projects.myproject]
path = "/data/repos/myproject"
```

## Directory Structure

```
/data/
├── repos/              # Clone your repositories here
├── worktrees/          # Git worktrees (one per agent/branch)
├── logs/<agent>/       # Logs per agent
├── home/agent/         # Persistent home directory
│   ├── .claude/        # Claude Code config & hooks
│   ├── .takopi/        # Takopi config & state
│   └── .ssh/           # SSH authorized_keys
└── config/
    ├── agentbox.toml   # Agent box settings
    ├── tailscale.state # Tailscale state
    └── ssh_host_*      # SSH host keys
```

## iOS Workflow

### Via Telegram (Easiest)

1. Open Telegram
2. Message your bot
3. Chat with Claude directly

### Via SSH

1. **Tailscale app**: Connect to your tailnet
2. **SSH app** (Blink/Termius): Save a profile for `agent@<tailscale-ip>:2222`
3. **On connect**: See MOTD with active agents
4. **Attach**: `cc-attach <agent-name>`
5. **Respond to Claude**: Type your response
6. **Detach**: `Ctrl-b d`

## Security

- **Tailscale-only access**: No public ports exposed
- **SSH key auth only**: Password auth disabled
- **Telegram encryption**: Bot token + chat ID authentication
- **Non-root user**: Agents run as `agent` user

## Troubleshooting

### Can't connect via SSH

- Check Tailscale is connected: `tailscale status`
- Verify SSH key is set: `fly secrets list`
- Check logs: `fly logs`

### Telegram not working

- Verify bot token: message @BotFather
- Check Takopi config: `cat ~/.takopi/takopi.toml`
- View Takopi logs: `takopi --verbose`

### Agent not starting

- Check tmux: `tmux ls`
- Check Claude Code: `which claude`
- View logs: `cat /data/logs/<agent>/`

## License

MIT
