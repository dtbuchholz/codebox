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
git clone https://github.com/your-org/codebox.git
cd codebox

# Initialize Fly config (creates app + volume interactively)
make fly-init APP=agent-box-<globally_unique_name>

# Set secrets
fly secrets set TAILSCALE_AUTHKEY="tskey-auth-xxx"
fly secrets set AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)"

# Optional: webhook auth token
fly secrets set WEBHOOK_AUTH_TOKEN="$(openssl rand -hex 16)"

# Deploy
fly deploy
```

> **Note**: The `fly-init.sh` script generates `fly.toml` from `fly.toml.example`.
> The generated `fly.toml` is gitignored since it contains your personal app name.

After deploy, find your Tailscale IP:

```bash
fly ssh console -C "tailscale ip -4"
```

### 2. Remote VM setup

You run these steps after SSH-ing into the VM.

```bash
# Use your app name as the Tailscale hostname (same as fly apps create)
ssh agent@agent-box-<yourname>
```

> **Note**: Tailscale SSH runs on port 22 (default). The `-p 2222` option is only needed
> for non-Tailscale SSH access, which isn't exposed by default.

Set up SSH keys for cloning private repos:

```bash
# Generate a deploy key (or copy your existing key)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
# Add this public key to your GitHub repo's deploy keys (Settings → Deploy keys)
```

Then, either add this public key to your GitHub repo's deploy keys (Settings → Deploy keys), or add it to your personal SSH keys:

1. Go to `github.com/settings/keys`
2. Click "New SSH key"
3. Paste the public key from above

Clone your repos into the persistent volume:

```bash
cd /data/repos
git clone git@github.com:your-org/your-repo.git
```

Authenticate GitHub CLI (for Claude to interact with issues, PRs, etc.):

```bash
gh auth login
# Follow prompts - choose HTTPS and authenticate via browser or token
```

Optional: configure project aliases and defaults:

```bash
cp /opt/config/agentbox.toml.example /data/config/agentbox.toml
vi /data/config/agentbox.toml
```

Optional: install Telegram support (Takopi):

```bash
# Install uv (adds itself to ~/.bashrc automatically)
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # or reconnect

# Install takopi
uv python install 3.13
uv tool install -U takopi
```

Configure Claude Code authentication. Choose one:

**Option A: Fly secrets (recommended - persists across restarts)**

```bash
# From your local machine:
fly secrets set ANTHROPIC_API_KEY="sk-ant-..."

# For OpenRouter/proxy:
fly secrets set ANTHROPIC_API_KEY="sk-or-v1-..." ANTHROPIC_BASE_URL="https://openrouter.ai/api"

# For voice transcription:
fly secrets set OPENAI_API_KEY="sk-..."
```

The entrypoint automatically exports these to the agent user's environment.

**Option B: bashrc (simpler, but may not survive all restarts)**

```bash
# On the VM:
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc

# For OpenRouter:
cat >> ~/.bashrc << 'EOF'
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_API_KEY="sk-or-v1-..."
EOF
```

> **Note**: Use `ANTHROPIC_API_KEY` (not `ANTHROPIC_AUTH_TOKEN`) with OpenRouter.

**Option C: Interactive login**

```bash
claude
# Then use /login when prompted
```

Optional: Add OpenAI key for voice transcription:

```bash
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc
```

After adding to bashrc, reload:

```bash
source ~/.bashrc
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

- Use `/ctx set myproject` to set project context
- Use `/ctx set myproject @branch` to set project and branch
- Use `/claude` to start a Claude session
- Send voice notes - they're transcribed automatically
- Send files - they're saved to the project

## Communication Options

### Option 1: Telegram via Takopi (Recommended)

Takopi provides secure, authenticated Telegram integration:

- **End-to-end encrypted** (Telegram's encryption)
- **Voice note transcription** (reply by voice, requires OPENAI_API_KEY)
- **File transfers** (send/receive files)
- **Session persistence** (resume conversations)
- **Forum topics** (one topic per agent)

**Setup steps:**

1. **Create a Telegram bot**: Message [@BotFather](https://t.me/BotFather) on Telegram
   - Send `/newbot` and follow prompts
   - Save the bot token (looks like `123456789:ABCdefGHI...`)

2. **Run the Takopi wizard** (recommended for first-time setup):

   ```bash
   takopi
   ```

   The wizard will guide you through configuration.

3. **Or configure manually**:

   ```bash
   mkdir -p ~/.takopi
   cp /opt/config/takopi.toml.example ~/.takopi/takopi.toml
   vi ~/.takopi/takopi.toml
   # Add your bot_token from step 1
   ```

4. **Get your chat ID**: Send any message to your bot. It will reply with your chat ID. Add this to your config.

   > **Note**: If your Telegram group was upgraded to a supergroup (e.g., when enabling topics),
   > the chat ID changes. Look for the new ID in the error message and update your config.

5. **Add your projects** to `~/.takopi/takopi.toml`:

   ```toml
   [projects.myproject]
   path = "/data/repos/myproject"
   ```

6. **Takopi auto-starts** on VM boot if configured. To manually start/restart:

   ```bash
   # Start Takopi (or restart if already running)
   tmux kill-session -t takopi 2>/dev/null; tmux new -s takopi -d 'bash -l -c takopi'

   # View logs
   tmux attach -t takopi
   # Press Ctrl-b d to detach
   ```

   > **Note**: If Takopi fails to start automatically, check `/data/logs/healthcheck.log` for errors.
   > The health check watchdog will attempt to restart Takopi and notify you via ntfy if configured.

> **Note**: If you configured Takopi locally first, copy the config to the VM:
>
> ```bash
> # Tailscale SSH may not support scp directly. Use ssh + cat instead:
> cat ~/.takopi/takopi.toml | ssh agent@agent-box-<yourname> 'mkdir -p ~/.takopi && cat > ~/.takopi/takopi.toml'
> ```

### Option 2: SSH + tmux

Direct terminal access via Tailscale:

```bash
ssh agent@agent-box-<yourname>
cc-attach myproject
```

### Multi-Device Access

You can access agents from both your phone and laptop, but the two access methods work differently:

| Method | How Claude runs | Multi-device access |
| ------ | --------------- | ------------------- |
| Telegram (Takopi) | Subprocess of Takopi | Open Telegram on any device |
| SSH (cc-* scripts) | tmux session | `cc-attach` from any SSH session |

**Takopi sessions** run Claude as a subprocess - you can't attach via SSH, but you can open Telegram on your laptop and message the same bot. Both devices see the same conversation.

**tmux sessions** (via `cc-new`/`cc-attach`) are independent from Takopi. Multiple SSH sessions can attach to the same tmux session simultaneously:

```bash
# Terminal 1 (laptop)
ssh agent@agent-box-yourname
cc-attach myagent

# Terminal 2 (another laptop, or phone via Blink/Termius)
ssh agent@agent-box-yourname
cc-attach myagent
# Both terminals now show the same Claude session
```

**Bridging both methods**: If you start a session via SSH and want to continue from Telegram (or vice versa), use Claude's resume feature:

```bash
# In SSH tmux session, note the session ID from Claude's output
# Then in Telegram:
/claude --resume <session-id> continue working on the feature
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

### Local (your machine)

| Command                            | Description                              |
| ---------------------------------- | ---------------------------------------- |
| `./scripts/fly-init.sh <app-name>` | Generate fly.toml, create Fly app/volume |
| `make fly-init APP=<name>`         | Same as above, via Makefile              |
| `fly deploy`                       | Deploy to Fly.io                         |
| `fly logs`                         | View Fly.io logs                         |

### Remote (on the VM)

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

**Fly.io secrets (set via `fly secrets set`):**

| Variable             | Description        | Default  |
| -------------------- | ------------------ | -------- |
| `TAILSCALE_AUTHKEY`  | Tailscale auth key | Required |
| `AUTHORIZED_KEYS`    | SSH public keys    | Required |
| `WEBHOOK_AUTH_TOKEN` | Webhook auth token | Optional |

**VM environment (add to `~/.bashrc`):**

| Variable             | Description                                | Default  |
| -------------------- | ------------------------------------------ | -------- |
| `ANTHROPIC_API_KEY`  | API key (Anthropic direct or OpenRouter)   | Optional |
| `ANTHROPIC_BASE_URL` | API proxy URL (e.g., `https://openrouter.ai/api`) | Optional |
| `OPENAI_API_KEY`     | For voice transcription                    | Optional |

> **Note**: For OpenRouter/proxy setups, use `ANTHROPIC_API_KEY` with your proxy's key
> (e.g., `sk-or-v1-...`). Also set `use_api_billing = true` in Takopi's `[claude]` config.

### Takopi Config (`~/.takopi/takopi.toml`)

```toml
watch_config = true  # Hot-reload config changes (no restart needed for new projects)
default_engine = "claude"
transport = "telegram"

[transports.telegram]
bot_token = "YOUR_BOT_TOKEN"
chat_id = 123456789
voice_transcription = true
session_mode = "chat"

[transports.telegram.topics]
enabled = true  # Use forum topics for multiple agents

[claude]
use_api_billing = true            # Required for OpenRouter/proxy setups
dangerously_skip_permissions = true  # Auto-approve tool calls

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
├── logs/
│   ├── <agent>/        # Logs per agent
│   └── healthcheck.log # Health monitor logs
├── home/agent/         # Persistent home directory
│   ├── .claude/        # Claude Code config & hooks
│   ├── .takopi/        # Takopi config & state
│   └── .ssh/           # SSH authorized_keys
└── config/
    ├── agentbox.toml   # Agent box settings
    ├── notify.conf     # Push notification settings
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
2. **SSH app** (Blink/Termius): Save a profile for `agent@agent-box-<yourname>` (port 22)
3. **On connect**: See MOTD with active agents
4. **Attach**: `cc-attach <agent-name>`
5. **Respond to Claude**: Type your response
6. **Detach**: `Ctrl-b d`

## Health Monitoring

Agent Box includes automatic health monitoring that:

- **Auto-starts Takopi** on VM boot (if configured)
- **Monitors services** (Takopi, Tailscale, SSH) every 60 seconds
- **Auto-restarts Takopi** if it crashes
- **Sends push notifications** via ntfy when issues are detected

### Setup Notifications

1. Create a unique ntfy topic at [ntfy.sh](https://ntfy.sh) or self-host
2. Configure on the VM:

   ```bash
   cp /opt/notify.conf.example /data/config/notify.conf
   vi /data/config/notify.conf
   # Set NTFY_TOPIC to your unique topic name
   ```

3. Subscribe to your topic in the ntfy app (iOS/Android) or web

### Health Check Commands

```bash
# Run health check manually
healthcheck.sh

# View health check logs
tail -f /data/logs/healthcheck.log

# Disable auto-restart (env var)
ENABLE_HEALTHCHECK=0
```

### What Gets Monitored

| Service | Check | Auto-Recovery |
| ------- | ----- | ------------- |
| Takopi | tmux session exists | Yes - restarts automatically |
| Tailscale | `tailscale status` | No - notifies only |
| SSH | `pgrep sshd` | No - notifies only |

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

### Fly app name already taken

- App names are global across Fly.io, not just your org.
- Pick a unique name and re-run: `./scripts/fly-init.sh agent-box-<newname>`

### Telegram not working

- Verify bot token: message @BotFather, use `/mybots` to check
- Check Takopi config: `cat ~/.takopi/takopi.toml`
- Ensure chat_id is set (bot tells you on first message)
- View Takopi logs: `takopi --verbose`

### Voice transcription not working

- Ensure OPENAI_API_KEY is set: `echo $OPENAI_API_KEY`
- Check it's exported in your shell config (~/.bashrc)

### Agent not starting

- Check tmux: `tmux ls`
- Check Claude Code: `which claude`
- View logs: `cat /data/logs/<agent>/`

### Environment variables not working

If you update `~/.bashrc`, existing tmux sessions won't pick up the changes.

**For agents (cc-new):**

```bash
cc-stop myagent
source ~/.bashrc
cc-new myagent /data/repos/myproject
```

**For Takopi:**

```bash
# If env vars were added after tmux server started, kill the server first
tmux kill-server
tmux new -s takopi -d 'bash -l -c takopi'
```

> **Note**: `tmux kill-session` only kills one session. If the tmux server was started
> before your env vars were set, use `tmux kill-server` to restart fresh.

### Takopi shows "Invalid API key"

This usually means Takopi isn't passing your API credentials to Claude Code correctly.

**If using OpenRouter or a proxy:**

1. Use `ANTHROPIC_API_KEY` (not `ANTHROPIC_AUTH_TOKEN`) in `~/.bashrc`:

   ```bash
   export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
   export ANTHROPIC_API_KEY="sk-or-v1-..."
   ```

2. Enable API billing mode in `~/.takopi/takopi.toml`:

   ```toml
   [claude]
   use_api_billing = true
   ```

   By default, Takopi strips `ANTHROPIC_API_KEY` from the environment to prefer
   subscription billing. Setting `use_api_billing = true` passes your env vars through
   unchanged.

3. Restart Takopi (use `kill-server`, not `kill-session`):

   ```bash
   tmux kill-server
   tmux new -s takopi -d 'bash -l -c takopi'
   ```

   > **Important**: `tmux kill-server` ensures the new session gets fresh environment
   > variables. `kill-session` alone may leave a stale tmux server with old env vars.

**General troubleshooting:**

- Ensure Claude Code auth is configured in `~/.bashrc` (see setup step)
- Restart Takopi with a login shell: `bash -l -c takopi`
- Verify env vars are set: `bash -l -c 'echo $ANTHROPIC_API_KEY'`
- Check that direct `claude` command works: `bash -l -c claude`

## License

MIT
