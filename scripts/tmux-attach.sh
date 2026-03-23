#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="${CLAUDE_SESSION_NAME:-claude}"

if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    echo "Attaching to Claude Code session '${SESSION_NAME}'..."
    echo "Detach with: Ctrl-b d"
    echo ""
    exec tmux attach-session -t "${SESSION_NAME}"
else
    echo "No active Claude Code tmux session found."
    echo ""
    echo "Available tmux sessions:"
    tmux list-sessions 2>/dev/null || echo "  (none)"
    echo ""
    echo "Starting a new Claude Code session..."
    exec tmux new-session -s "${SESSION_NAME}" "claude --dangerously-skip-permissions; exec bash"
fi
