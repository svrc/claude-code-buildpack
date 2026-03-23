#!/usr/bin/env bash
# lib/environment.sh: CNB v3 environment variable setup via env.launch/ files

# Set up env.launch/ layer for Claude Code environment variables
setup_env_launch() {
    local layers_dir=$1
    local config_file=$2

    local layer_dir="${layers_dir}/claude-env"
    local env_dir="${layer_dir}/env.launch"

    mkdir -p "${env_dir}"

    local log_level="info"
    local model="sonnet"
    if [ -f "${config_file}" ]; then
        local parsed
        parsed=$(grep -E "^[[:space:]]*logLevel:" "${config_file}" | sed -E 's/^[[:space:]]*logLevel:[[:space:]]*(.+)[[:space:]]*$/\1/' | tr -d '"' | tr -d "'")
        [ -n "${parsed}" ] && log_level="${parsed}"
        parsed=$(grep -E "^[[:space:]]*model:" "${config_file}" | sed -E 's/^[[:space:]]*model:[[:space:]]*(.+)[[:space:]]*$/\1/' | tr -d '"' | tr -d "'")
        [ -n "${parsed}" ] && model="${parsed}"
    fi

    # Write env var files (.default = set only if not already set)
    printf '%s' "${log_level}" > "${env_dir}/CLAUDE_CODE_LOG_LEVEL.default"
    printf '%s' "${model}" > "${env_dir}/CLAUDE_CODE_MODEL.default"
    printf '%s' "xterm-256color" > "${env_dir}/TERM.default"
    printf '%s' "1" > "${env_dir}/CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC.default"
    printf '%s' "1" > "${env_dir}/DISABLE_AUTOUPDATER.default"

    cat > "${layers_dir}/claude-env.toml" <<'EOF'
[types]
launch = true
EOF

    local execd_dir="${layer_dir}/exec.d"
    mkdir -p "${execd_dir}"
    cp "${CNB_BUILDPACK_DIR}/exec.d/claude-env" "${execd_dir}/claude-env"
    chmod +x "${execd_dir}/claude-env"
}

# Validate API key or OAuth token availability
setup_api_key() {
    local api_key="${ANTHROPIC_API_KEY:-}"
    local oauth_token="${CLAUDE_CODE_OAUTH_TOKEN:-}"

    # Check platform env files (CNB convention)
    if [ -z "${api_key}" ] && [ -n "${CNB_PLATFORM_DIR:-}" ]; then
        api_key=$(cat "${CNB_PLATFORM_DIR}/env/ANTHROPIC_API_KEY" 2>/dev/null) || true
    fi
    if [ -z "${oauth_token}" ] && [ -n "${CNB_PLATFORM_DIR:-}" ]; then
        oauth_token=$(cat "${CNB_PLATFORM_DIR}/env/CLAUDE_CODE_OAUTH_TOKEN" 2>/dev/null) || true
    fi

    if [ -z "${api_key}" ] && [ -z "${oauth_token}" ]; then
        echo "       WARNING: Neither ANTHROPIC_API_KEY nor CLAUDE_CODE_OAUTH_TOKEN is set"
        echo "       Claude Code will not function without authentication"
        return 1
    fi

    if [ -n "${api_key}" ]; then
        echo "       API key detected (not logged for security)"
    elif [ -n "${oauth_token}" ]; then
        echo "       OAuth token detected (not logged for security)"
    fi
    return 0
}
