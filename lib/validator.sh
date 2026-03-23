#!/usr/bin/env bash
# lib/validator.sh: Validation utilities for buildpack

# Validate environment and prerequisites for CNB v3 build
validate_environment() {
    echo "       Checking prerequisites..."

    # Check for required commands
    if ! command -v curl &> /dev/null; then
        echo "       ERROR: curl is required but not installed"
        return 1
    fi

    if ! command -v tar &> /dev/null; then
        echo "       ERROR: tar is required but not installed"
        return 1
    fi

    if ! command -v python3 &> /dev/null; then
        echo "       ERROR: python3 is required for YAML parsing but not installed"
        return 1
    fi

    # Resolve API key: check CNB platform dir files first, then env vars
    local api_key="${ANTHROPIC_API_KEY}"
    if [ -z "${api_key}" ] && [ -n "${CNB_PLATFORM_DIR}" ] && [ -f "${CNB_PLATFORM_DIR}/env/ANTHROPIC_API_KEY" ]; then
        api_key=$(cat "${CNB_PLATFORM_DIR}/env/ANTHROPIC_API_KEY")
        export ANTHROPIC_API_KEY="${api_key}"
    fi

    local oauth_token="${CLAUDE_CODE_OAUTH_TOKEN}"
    if [ -z "${oauth_token}" ] && [ -n "${CNB_PLATFORM_DIR}" ] && [ -f "${CNB_PLATFORM_DIR}/env/CLAUDE_CODE_OAUTH_TOKEN" ]; then
        oauth_token=$(cat "${CNB_PLATFORM_DIR}/env/CLAUDE_CODE_OAUTH_TOKEN")
        export CLAUDE_CODE_OAUTH_TOKEN="${oauth_token}"
    fi

    # Validate authentication
    if [ -z "${api_key}" ] && [ -z "${oauth_token}" ]; then
        echo "       WARNING: Neither ANTHROPIC_API_KEY nor CLAUDE_CODE_OAUTH_TOKEN is set"
        echo "       Claude Code requires authentication to function"
        echo "       Provide credentials via environment variables or platform env files"
    elif [ -n "${api_key}" ]; then
        if [[ ! "${api_key}" =~ ^sk-ant- ]]; then
            echo "       WARNING: ANTHROPIC_API_KEY format appears invalid"
            echo "       Expected format: sk-ant-..."
        else
            echo "       API key format validated"
        fi
    elif [ -n "${oauth_token}" ]; then
        echo "       OAuth token detected (using CLAUDE_CODE_OAUTH_TOKEN)"
    fi

    return 0
}

# Validate configuration file
validate_config_file() {
    local config_file=$1

    if [ ! -f "${config_file}" ]; then
        echo "       ERROR: Configuration file not found: ${config_file}"
        return 1
    fi

    # Basic YAML validation (check if file is readable)
    if [ ! -r "${config_file}" ]; then
        echo "       ERROR: Configuration file not readable: ${config_file}"
        return 1
    fi

    echo "       Configuration file validated"
    return 0
}

# Validate Node.js version
validate_nodejs_version() {
    local node_version=$1

    # Check if version string is valid (basic check)
    if [[ ! "${node_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "       ERROR: Invalid Node.js version format: ${node_version}"
        echo "       Expected format: X.Y.Z (e.g., 20.11.0)"
        return 1
    fi

    return 0
}

# Validate installation directory
validate_install_dir() {
    local install_dir=$1

    if [ ! -d "${install_dir}" ]; then
        echo "       ERROR: Installation directory does not exist: ${install_dir}"
        return 1
    fi

    if [ ! -w "${install_dir}" ]; then
        echo "       ERROR: Installation directory is not writable: ${install_dir}"
        return 1
    fi

    return 0
}

# Validate MCP server configuration (basic)
validate_mcp_config() {
    local config=$1

    # This is a placeholder for Phase 2
    # In Phase 2, we'll implement proper MCP configuration validation

    echo "       MCP validation (Phase 2 feature)"
    return 0
}

# Check if a command exists
command_exists() {
    local cmd=$1
    command -v "${cmd}" &> /dev/null
}

# Validate required tools
validate_required_tools() {
    local missing_tools=()

    local required_tools=("curl" "tar" "mkdir" "chmod" "ln")

    for tool in "${required_tools[@]}"; do
        if ! command_exists "${tool}"; then
            missing_tools+=("${tool}")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "       ERROR: Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    echo "       All required tools are available"
    return 0
}
