# Claude Code Environment Buildpack (CNB v3)

General-purpose Cloud Native Buildpack (CNB) v3 that installs Claude Code CLI, Node.js, and tmux. Designed for Korifi environments, this buildpack enables AI-assisted coding sessions within your application containers and supports state persistence by pushing the `.claude/` directory.

## Overview

This buildpack provides a complete environment for Claude Code CLI. It manages the installation of Node.js, the Claude Code CLI itself, and tmux for persistent session management. It's optimized for Korifi and handles runtime state restoration from your pushed application source.

## Features

- Claude Code CLI installation and configuration
- Persistent tmux sessions for long-running AI tasks
- State persistence via `.claude/` directory push
- MCP (Model Context Protocol) server support (stdio, SSE, HTTP)
- Skills support for custom instructions and tools
- Built-in health check endpoint for container readiness
- Non-root execution (runs as `cnb` user)

## Quick Start

### 1. Package and Publish the Buildpack

```bash
make publish REGISTRY=your-registry
```

### 2. Register with Korifi

Patch your Korifi ClusterStore and ClusterBuilder to include the buildpack:

```bash
# Example registration (adjust for your environment)
kubectl patch clusterstore default --type merge -p '{"spec":{"sources":[{"image":"your-registry/claude-code:latest"}]}}'
kubectl patch clusterbuilder default --type merge -p '{"spec":{"order":[{"group":[{"id":"io.tanzu.buildpacks.claude-code"}]}]}}'
```

### 3. Set Up Your Application

Organize your application directory:

```
my-app/
├── .claude-code-config.yml   # Optional: MCP servers, settings
├── .claude/                   # Optional: sessions, memory, settings to restore
│   ├── settings.json
│   ├── CLAUDE.md
│   └── transcripts/
├── .claude.json               # Optional: per-project MCP config
└── (your app files)
```

### 4. Deploy

```bash
cf push my-app -b io.tanzu.buildpacks.claude-code
```

### 5. Access Claude Code

Since `cf ssh` is not available in Korifi, use `kubectl exec` to attach to the tmux session:

```bash
kubectl exec -it <pod-name> -- /workspace/scripts/tmux-attach.sh
```

## Detection

The buildpack activates when any of the following are detected in the application root:
- `.claude-code-config.yml` file
- `.claude/` directory
- `CLAUDE_CODE_ENABLED=true` environment variable

## Configuration

### .claude-code-config.yml

You can configure Claude Code using `.claude-code-config.yml` in your application root:

```yaml
claudeCode:
  enabled: true

  # Log level - controls verbosity of CLI output
  # Options: debug, info, warn, error
  # Default: info
  logLevel: debug

  # Claude Code CLI version
  # Default: latest
  version: "latest"

  # Default Claude model to use
  # Options: sonnet, opus, haiku
  # Default: sonnet
  model: sonnet

  # Claude settings (written to ~/.claude/settings.json)
  settings:
    # Enable extended thinking for complex multi-step operations
    # Default: true (automatically enabled by buildpack)
    alwaysThinkingEnabled: true

  # MCP servers configuration
  mcpServers:
    - name: filesystem
      type: stdio
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-filesystem"
      env:
        ALLOWED_DIRECTORIES: "/workspace,/tmp"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key | (Required) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Alternative OAuth token | - |
| `BP_NODE_VERSION` | Node.js version to install | `20.x` |
| `BP_CLAUDE_CODE_VERSION` | Claude Code version to install | `latest` |
| `CLAUDE_SESSION_NAME` | Name for the tmux session | `claude` |
| `CLAUDE_RESUME_SESSION` | Set to `true` to resume existing session state | `false` |

## Session Management

### State Persistence

To persist Claude's memory, transcripts, and settings across deployments, include the `.claude/` directory in your application source when pushing. The buildpack restores this state to the runtime home directory during container startup.

### Resuming Sessions

Set `CLAUDE_RESUME_SESSION=true` to ensure Claude attempts to pick up where it left off using the restored state in `.claude/`.

## Container Access

In Korifi environments, use the provided helper script to attach to the Claude tmux session:

```bash
kubectl exec -it <pod-name> -- /workspace/scripts/tmux-attach.sh
```

This script ensures you attach to the correct tmux session with the proper environment variables loaded.

## Process Types

The buildpack defines two process types:

- **web**: The default process. Starts a health check server on `$PORT` and initializes the Claude tmux session in the background.
- **claude**: A standalone process that only runs the Claude tmux session.

## Layer Architecture

The buildpack organizes its dependencies into distinct layers:

- **node**: The Node.js runtime.
- **claude-code**: The Claude Code CLI and its global npm modules.
- **tmux**: The tmux binary and configuration.
- **claude-env**: Runtime scripts and environment configuration.

## MCP (Model Context Protocol) Servers

Claude Code supports MCP servers to extend its capabilities. The buildpack generates the necessary `.claude.json` from your `.claude-code-config.yml`.

### Supported Transports

- **stdio**: Local processes communicating via standard I/O.
- **sse**: Remote servers using Server-Sent Events.
- **http**: Remote servers using standard HTTP requests.

Example remote configuration:

```yaml
mcpServers:
  - name: remote-service
    type: sse
    url: "https://mcp.example.com/sse"
```

## Skills

Skills are modular folders containing a `SKILL.md` file. Place them in `.claude/skills/` in your application root. Claude autonomously decides when to use them based on their description.

### SKILL.md Format

```markdown
---
name: my-skill
description: Explains what this skill does.
---
# Instructions
Detailed instructions for Claude...
```

## Packaging and Registration

### Packaging

```bash
# Create a buildpackage
make package

# Publish to a registry
make publish REGISTRY=your-registry
```

### Registration with Korifi

The buildpack must be added to the `ClusterStore` and referenced in a `ClusterBuilder`.

```yaml
# Example ClusterStore entry
apiVersion: kpack.io/v1alpha2
kind: ClusterStore
metadata:
  name: default
spec:
  sources:
  - image: your-registry/claude-code-buildpack:latest
```

## Development

### Prerequisites

- Docker
- pack CLI
- make

### Commands

- `make test`: Run the test suite
- `make lint`: Run linting checks
- `make package`: Build the buildpack locally

## Known Limitations

- **No cf ssh**: Korifi does not support `cf ssh`. Use `kubectl exec` instead.
- **Ephemeral Filesystem**: Changes made to the filesystem at runtime are lost on restart. State must be managed via the `.claude/` directory in the application source.
- **Non-root User**: The buildpack runs as the `cnb` user (UID 1000). Ensure your application files and scripts are compatible with non-root execution.
- **Workspace Path**: The application source is located at `/workspace`, not `/home/vcap/app`.
