# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

**See [AGENTS.md](./AGENTS.md) for complete project context, architecture, and coding guidelines.**

## Claude Code Workflow

1. **Read AGENTS.md first** - It contains all project structure, commands, and conventions
2. **Run `make setup`** before starting work (installs hooks and checks tools)
3. **Use todo lists** - Track multi-step tasks with the TodoWrite tool
4. **Commit frequently** - Small, focused commits after each logical change
5. **Never bypass hooks** - Fix issues, don't use `--no-verify`

## Quick Reference

```bash
make setup    # First-time setup (hooks + tool check)
make lint     # Run all linters
make qa       # Full QA: lint + test + build
make deploy   # Deploy to Fly.io
```

## Key Files

| File                   | Purpose                          |
| ---------------------- | -------------------------------- |
| `webhook/main.go`      | HTTP server for reply-from-phone |
| `scripts/cc-*`         | Agent lifecycle commands         |
| `config/entrypoint.sh` | Container startup                |
| `Dockerfile`           | Multi-stage build                |
| `fly.toml`             | Fly.io config                    |
