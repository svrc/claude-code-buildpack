#!/usr/bin/env bash
set -euo pipefail

# Web process entrypoint: starts Claude Code in a tmux session, then runs the health check.
# The health check keeps Korifi happy (responds on $PORT), while Claude runs in background tmux.
# Attach to the Claude session via: kubectl exec -it <pod> -- /workspace/scripts/tmux-attach.sh

SESSION_NAME="${CLAUDE_SESSION_NAME:-claude}"
RESUME_SESSION="${CLAUDE_RESUME_SESSION:-}"

CLAUDE_ARGS=(--dangerously-skip-permissions)

if [ -n "${RESUME_SESSION}" ]; then
    CLAUDE_ARGS+=(--resume "${RESUME_SESSION}")
elif [ -n "${CLAUDE_SESSION_NAME:-}" ]; then
    CLAUDE_ARGS+=(-n "${SESSION_NAME}")
fi

tmux new-session -d -s "${SESSION_NAME}" -x 200 -y 50 \
    "claude ${CLAUDE_ARGS[*]}; exec bash"

exec node /workspace/scripts/health-check.js
