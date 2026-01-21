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
./scripts/fly-init.sh agent-box-<yourname>

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

**Option A: Anthropic API directly**
```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
```

**Option B: OpenRouter (or other proxy)**
```bash
cat >> ~/.bashrc << 'EOF'
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_AUTH_TOKEN="sk-or-v1-..."
export ANTHROPIC_API_KEY=""
EOF
```

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

6. **Run Takopi** in a tmux session (so it persists after disconnect):

   ```bash
   # Use bash -l to ensure environment variables from ~/.bashrc are loaded
   tmux new -s takopi -d 'bash -l -c takopi'
   
   # View logs
   tmux attach -t takopi
   # Press Ctrl-b d to detach
   ```

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

| Command                             | Description                              |
| ----------------------------------- | ---------------------------------------- |
| `./scripts/fly-init.sh <app-name>`  | Generate fly.toml, create Fly app/volume |
| `make fly-init APP=<name>`          | Same as above, via Makefile              |
| `fly deploy`                        | Deploy to Fly.io                         |
| `fly logs`                          | View Fly.io logs                         |

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

| Variable             | Description             | Default  |
| -------------------- | ----------------------- | -------- |
| `TAILSCALE_AUTHKEY`  | Tailscale auth key      | Required |
| `AUTHORIZED_KEYS`    | SSH public keys         | Required |
| `WEBHOOK_AUTH_TOKEN` | Webhook auth token      | Optional |

**VM environment (add to `~/.bashrc`):**

| Variable               | Description                          | Default  |
| ---------------------- | ------------------------------------ | -------- |
| `ANTHROPIC_API_KEY`    | Anthropic API key (direct)           | Optional |
| `ANTHROPIC_BASE_URL`   | API proxy URL (e.g., OpenRouter)     | Optional |
| `ANTHROPIC_AUTH_TOKEN` | Auth token for proxy                 | Optional |
| `OPENAI_API_KEY`       | For voice transcription              | Optional |

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
2. **SSH app** (Blink/Termius): Save a profile for `agent@agent-box-<yourname>` (port 22)
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
tmux kill-session -t takopi
tmux new -s takopi -d 'bash -l -c takopi'
```

### Takopi shows "Invalid API key"

- Ensure Claude Code auth is configured in `~/.bashrc` (see setup step)
- Restart Takopi with a login shell: `bash -l -c takopi`
- Verify env vars are set: `echo $ANTHROPIC_API_KEY` (or `$ANTHROPIC_AUTH_TOKEN`)

## License

MIT
