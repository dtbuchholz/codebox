# Agent Box

A remote "agent box" on Fly.io for running long-lived Claude Code sessions inside tmux. Connect via SSH from anywhere (including iOS), and interact via Telegram with voice support.

## Features

- **Persistent sessions**: Run Claude Code in tmux sessions that survive disconnects
- **Multi-agent support**: Run multiple agents in parallel with isolated working directories
- **Telegram integration**: Chat with agents via [Takopi](https://takopi.dev) - text, voice, files
- **Phone-first access**: Connect via Tailscale + SSH from iOS (Blink, Termius)
- **Git worktrees**: Each agent can work on its own branch without conflicts
- **Dev tools included**: PostgreSQL, pnpm, gh CLI, and more pre-installed

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

### Phase 1: Local Setup

Run these on your laptop/desktop.

**Prerequisites:**

- [Fly.io account](https://fly.io) + `flyctl`
- [Tailscale account](https://tailscale.com)
- SSH key pair

**Recommended VM specs:**

| Resource | Minimum       | Recommended   |
| -------- | ------------- | ------------- |
| CPU      | shared-cpu-2x | shared-cpu-4x |
| Memory   | 4 GB          | 8 GB          |
| Volume   | 10 GB         | 10 GB+        |

The defaults in `fly.toml.example` use minimum specs. For running multiple agents or larger codebases, increase to recommended specs by editing `fly.toml` after generation.

```bash
# Clone and initialize
git clone https://github.com/your-org/codebox.git
cd codebox

# Create Fly app and volume
make fly-init APP=agent-box-<unique_name>

# Set required secrets
fly secrets set TAILSCALE_AUTHKEY="tskey-auth-xxx"
fly secrets set AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)"

# Deploy
fly deploy
```

After deploy, get your Tailscale IP:

```bash
fly ssh console -C "tailscale ip -4"
```

### Phase 2: VM Setup

SSH into the VM and run the setup wizard:

```bash
ssh agent@agent-box-<yourname>   # Tailscale hostname
vm-setup                          # Interactive setup wizard
```

The wizard configures git, GitHub CLI, SSH keys, and optionally Takopi.

**Or configure manually:**

```bash
# SSH key for GitHub
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
# Add to github.com/settings/keys

# Clone repos
cd /data/repos
git clone git@github.com:your-org/your-repo.git

# GitHub CLI
gh auth login

# Git identity
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

**Claude Code authentication** (choose one):

```bash
# Option A: Fly secrets (recommended)
fly secrets set ANTHROPIC_API_KEY="sk-ant-..."

# Option B: bashrc
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
source ~/.bashrc

# Option C: Interactive login
claude   # then use /login
```

### Phase 3: Start Using Agents

```bash
# Create an agent
cc-new myproject /data/repos/myproject

# Or with git worktree
cc-new feature @myproject/feature-branch

# List agents
cc-ls

# Attach to agent
cc-attach myproject

# Detach: Ctrl-b d
```

## Agent Commands

| Command                         | Description                    |
| ------------------------------- | ------------------------------ |
| `cc-new <name> <dir>`           | Create agent in directory      |
| `cc-new <name> @project/branch` | Create agent with git worktree |
| `cc-new <name> <dir> --attach`  | Create and attach immediately  |
| `cc-ls`                         | List all running agents        |
| `cc-attach <name>`              | Attach to existing agent       |
| `cc-stop <name>`                | Stop an agent                  |
| `cc-stop --all`                 | Stop all agents                |
| `vm-setup`                      | Interactive setup wizard       |
| `init-admin`                    | Create orchestrator workspace  |
| `takopi-restart`                | Restart Takopi bot             |
| `takopi-add-project <name>`     | Add project to Takopi config   |

### Orchestrator Workspace

For general VM tasks (cloning repos, system management), create an orchestrator workspace:

```bash
cd /data/repos
init-admin
```

This creates `/data/repos/_admin` with a CLAUDE.md tailored for VM-wide tasks. Map it to your Telegram "General" topic via `/ctx set _admin`.

## Communication Options

### Telegram via Takopi (Recommended)

Takopi provides secure Telegram integration with voice transcription and file transfers.

**Setup:**

1. Create a bot via [@BotFather](https://t.me/BotFather) → `/newbot`
2. Run `takopi` on the VM (wizard guides you through config)
3. Or manually configure `~/.takopi/takopi.toml`:

```toml
watch_config = true
default_engine = "claude"
transport = "telegram"

[transports.telegram]
bot_token = "YOUR_BOT_TOKEN"
chat_id = 123456789
voice_transcription = true

[transports.telegram.topics]
enabled = true

[claude]
use_api_billing = true
dangerously_skip_permissions = true

[projects.myproject]
path = "/data/repos/myproject"
```

4. Add projects: `takopi-add-project myproject`
5. Set up forum topics in Telegram, bind with `/ctx set myproject`

**Commands:**

```bash
takopi-restart             # Restart (clears lockfile)
takopi-restart --upgrade   # Upgrade and restart
takopi-restart --status    # Check status
```

### SSH + tmux

Direct terminal access via Tailscale:

```bash
ssh agent@agent-box-<yourname>
cc-attach myproject
# Detach: Ctrl-b d
```

### Webhook (Legacy)

HTTP webhook for custom integrations:

```bash
curl -X POST "http://<tailscale-ip>:8080/send" \
  -H "Authorization: Bearer $TOKEN" \
  -d "agent=myproject" \
  -d "message=your response"
```

### Multi-Device Access

| Method   | How Claude runs      | Multi-device                        |
| -------- | -------------------- | ----------------------------------- |
| Telegram | Subprocess of Takopi | Open Telegram on any device         |
| SSH      | tmux session         | `cc-attach` from any SSH connection |

Multiple SSH sessions can attach to the same tmux session simultaneously.

## Configuration

### Fly.io Secrets

Set via `fly secrets set`:

| Variable             | Description                     | Required        |
| -------------------- | ------------------------------- | --------------- |
| `TAILSCALE_AUTHKEY`  | Tailscale auth key              | Yes             |
| `AUTHORIZED_KEYS`    | SSH public keys                 | Yes             |
| `ANTHROPIC_API_KEY`  | Claude API key                  | No              |
| `OPENAI_API_KEY`     | For Takopi voice transcription  | No              |
| `WEBHOOK_AUTH_TOKEN` | Webhook auth token              | No              |
| `CLAUDE_CONFIG_REPO` | Git repo for Claude config sync | No              |
| `AUTO_UPDATE_CLAUDE` | Auto-update Claude Code on boot | No (default: 1) |

### VM Environment (`~/.bashrc`)

| Variable             | Description                       |
| -------------------- | --------------------------------- |
| `ANTHROPIC_API_KEY`  | API key (Anthropic or OpenRouter) |
| `ANTHROPIC_BASE_URL` | Proxy URL (e.g., OpenRouter)      |
| `OPENAI_API_KEY`     | For voice transcription           |

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

### Claude Config Sync

Sync Claude Code settings from a git repo:

```bash
# Set repo URL
fly secrets set CLAUDE_CONFIG_REPO=https://github.com/user/claude-config

# Manual sync
claude-config-sync
claude-config-sync --init    # First-time clone
claude-config-sync --status  # Check status
```

The repo structure should match `~/.claude/`:

```
claude-config/
├── settings.json
└── settings.local.json
```

## Directory Structure

```
/data/                    # Persistent Fly volume
├── repos/                # Git repositories
├── worktrees/            # Git worktrees (one per agent/branch)
├── logs/
│   ├── <agent>/          # Logs per agent
│   └── healthcheck.log   # Health monitor logs
├── home/agent/           # Persistent home directory
│   ├── .claude/          # Claude Code config & hooks
│   ├── .takopi/          # Takopi config & state
│   └── .ssh/             # SSH keys
└── config/
    ├── agentbox.toml     # Agent box settings
    ├── tailscale.state   # Tailscale state
    └── ssh_host_*        # SSH host keys
```

## Pre-installed Tools

| Tool                | Description                            |
| ------------------- | -------------------------------------- |
| `claude`            | Claude Code CLI                        |
| `gh`                | GitHub CLI                             |
| `git`               | Version control                        |
| `psql`              | PostgreSQL client (server auto-starts) |
| `pnpm`              | Node.js package manager                |
| `node`              | Node.js 22.x LTS                       |
| `yazi`              | Terminal file manager                  |
| `vim`, `htop`, `jq` | Common utilities                       |

## Health Monitoring

Agent Box monitors services every 60 seconds:

| Service   | Check               | Auto-Recovery |
| --------- | ------------------- | ------------- |
| Takopi    | tmux session exists | Yes           |
| Tailscale | `tailscale status`  | No            |
| SSH       | `pgrep sshd`        | No            |
| Memory    | warns < 200MB free  | No            |

```bash
# View logs
tail -f /data/logs/healthcheck.log

# Disable watchdog
ENABLE_HEALTHCHECK=0
```

## Security

- **Tailscale-only access**: No public ports exposed
- **SSH key auth only**: Password auth disabled
- **Signed commits**: SSH signing for verified commits
- **Protected branches**: Claude Code blocked from pushing to main/master
- **Non-root user**: Agents run as `agent` user

### SSH Commit Signing

Agent Box uses SSH keys for commit signing (Git 2.34+). This creates "Verified" commits on GitHub without GPG complexity.

**Setup via wizard:**

```bash
vm-setup   # Prompts to enable SSH signing
```

**Manual setup:**

```bash
# Configure git to use SSH signing
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# Create allowed_signers file
echo "your@email.com $(cat ~/.ssh/id_ed25519.pub)" > ~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

# Set author env vars (required for Claude Code with API key auth)
cat >> ~/.bashrc << 'EOF'
export GIT_AUTHOR_NAME="Your Name"
export GIT_AUTHOR_EMAIL="your@email.com"
export GIT_COMMITTER_NAME="Your Name"
export GIT_COMMITTER_EMAIL="your@email.com"
EOF
source ~/.bashrc
```

> **Why the env vars?** When using API key auth (not OAuth), Claude Code doesn't know your identity and defaults to `claude@anthropic.com` as the commit author. These env vars ensure commits use your identity.

**Add signing key to GitHub:**

1. Go to https://github.com/settings/ssh/new
2. Select **Signing Key** (not Authentication Key)
3. Paste your public key (`~/.ssh/id_ed25519.pub`)

> **Note:** The same SSH key can be added twice to GitHub - once as Authentication Key and once as Signing Key.

### Branch Protection

Claude Code is configured to block pushes to main/master via a PreToolUse hook:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "/usr/local/bin/claude-hook-check-push" }]
      }
    ]
  }
}
```

Enable with: `fly secrets set USE_CLAUDE_SETTINGS_TEMPLATE=1`

Optional git pre-push hook for additional protection:

```bash
cp /opt/git-hooks/pre-push /data/repos/myproject/.git/hooks/
```

## iOS Workflow

### Via Telegram

1. Open Telegram
2. Message your bot
3. Chat with Claude directly

### Via SSH

1. Connect Tailscale app
2. SSH app (Blink/Termius): `agent@agent-box-<yourname>` port 22
3. Attach: `cc-attach <agent-name>`
4. Detach: `Ctrl-b d`

## Troubleshooting

### Connection Issues

**Can't connect via SSH:**

```bash
tailscale status          # Check Tailscale
fly secrets list          # Verify SSH key set
fly logs                  # Check logs
```

**Fly app name taken:** Names are global. Pick unique name: `./scripts/fly-init.sh agent-box-<newname>`

### Telegram Issues

**Bot not responding:**

```bash
cat ~/.takopi/takopi.toml  # Check config
takopi --verbose           # Debug mode
```

**Voice not working:** Set OpenAI API key via Fly secrets:

```bash
fly secrets set OPENAI_API_KEY="sk-..."
```

The machine restarts automatically to pick up new secrets.

### Agent Issues

**Agent not starting:**

```bash
tmux ls                    # Check tmux
which claude               # Verify Claude installed
cat /data/logs/<agent>/    # View logs
```

**Environment variables not working:**

```bash
# For agents
cc-stop myagent && source ~/.bashrc && cc-new myagent /path

# For Takopi
takopi-restart
```

> Note: `tmux kill-server` restarts all sessions with fresh env.

### API Key Issues

**"Invalid API key" with OpenRouter:**

1. Use `ANTHROPIC_API_KEY` (not `ANTHROPIC_AUTH_TOKEN`)
2. Set `use_api_billing = true` in `~/.takopi/takopi.toml`
3. Run `takopi-restart`

### Disk Space Issues

**"No space left on device" errors:**

The default 10GB volume can fill up quickly with JS projects. Check usage:

```bash
df -h /data                                    # Overall usage
du -sh /data/repos/*                           # Repo sizes
du -sh /data/home/agent/.local/share/* 2>/dev/null | sort -h  # Caches
```

**Common space hogs:**

| Location                 | Typical Size | Description                    |
| ------------------------ | ------------ | ------------------------------ |
| `~/.local/share/pnpm`    | 2-5GB        | pnpm content-addressable store |
| `~/.cache/ms-playwright` | 900MB        | Browser binaries for E2E tests |
| `~/.local/share/uv`      | 200-500MB    | Python environments (Takopi)   |
| `/data/swapfile`         | 2GB          | Swap file (do not delete)      |

**Cleanup commands:**

```bash
pnpm store prune                   # Remove unused pnpm packages
rm -rf ~/.cache/ms-playwright      # Remove Playwright browsers
rm -rf ~/.cache/node-gyp           # Remove node-gyp cache
npm cache clean --force            # Clear npm cache
```

**Extend volume (from local machine):**

```bash
fly volumes list -a <app-name>
fly volumes extend <vol-id> -s 20  # Extend to 20GB ($0.15/GB/month)
fly machines restart <machine-id>  # Restart to resize filesystem
```

### Performance Issues

**VM freezes during heavy operations:**

```bash
fly machines list                  # Get machine ID
fly machines restart <machine-id>  # Restart

# Prevent: increase memory
fly scale memory 4096
```

Swap (2GB) is auto-configured. Check for OOM: `dmesg | grep -i "out of memory"`

## Local Development

```bash
make setup        # Install hooks
make lint         # Run linters
make test         # Run tests
make qa           # Full QA suite
make build        # Build Docker image
make deploy       # Deploy to Fly.io
```

## License

MIT
