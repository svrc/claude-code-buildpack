#!/usr/bin/env bash
# lib/installer.sh: CNB v3 layer-based installation for Node.js, Claude Code CLI, and tmux

set -euo pipefail

read_toml_metadata() {
    local toml_file="$1"
    local key="$2"
    if [[ -f "$toml_file" ]]; then
        grep "^${key} " "$toml_file" 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/' || echo ""
    else
        echo ""
    fi
}

write_layer_toml() {
    local toml_file="$1"
    local launch="$2"
    local build="$3"
    local cache="$4"
    shift 4

    cat > "$toml_file" <<EOF
[types]
launch = ${launch}
build = ${build}
cache = ${cache}
EOF

    if [[ $# -gt 0 ]]; then
        echo "" >> "$toml_file"
        echo "[metadata]" >> "$toml_file"
        while [[ $# -gt 0 ]]; do
            echo "$1" >> "$toml_file"
            shift
        done
    fi
}

install_nodejs() {
    local layers_dir="$1"
    local node_version="${NODE_VERSION:-22.12.0}"
    local layer_dir="${layers_dir}/node"
    local toml_file="${layers_dir}/node.toml"

    local cached_version
    cached_version=$(read_toml_metadata "$toml_file" "node_version")

    if [[ "$cached_version" == "$node_version" && -x "${layer_dir}/bin/node" ]]; then
        echo "-----> Using cached Node.js v${node_version}"
        export PATH="${layer_dir}/bin:${PATH}"
        return 0
    fi

    echo "-----> Installing Node.js v${node_version}"

    rm -rf "$layer_dir"
    mkdir -p "$layer_dir"

    local arch
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        *)       echo "ERROR: Unsupported architecture: $(uname -m)"; return 1 ;;
    esac

    local url="https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-${arch}.tar.xz"
    local tmp_archive
    tmp_archive="$(mktemp /tmp/node-XXXXXX.tar.xz)"

    if ! curl -sSL "$url" -o "$tmp_archive"; then
        echo "ERROR: Failed to download Node.js from ${url}"
        rm -f "$tmp_archive"
        return 1
    fi

    if ! tar xJf "$tmp_archive" -C "$layer_dir" --strip-components=1; then
        echo "ERROR: Failed to extract Node.js"
        rm -f "$tmp_archive"
        return 1
    fi

    rm -f "$tmp_archive"

    if [[ ! -x "${layer_dir}/bin/node" ]]; then
        echo "ERROR: Node.js binary not found after extraction"
        return 1
    fi

    write_layer_toml "$toml_file" "true" "true" "true" \
        "node_version = \"${node_version}\""

    export PATH="${layer_dir}/bin:${PATH}"

    echo "       Node.js v${node_version} installed"
    return 0
}

install_claude_code() {
    local layers_dir="$1"
    local requested_version="${CLAUDE_CODE_VERSION:-latest}"
    local layer_dir="${layers_dir}/claude-code"
    local toml_file="${layers_dir}/claude-code.toml"
    local npm_bin="${layers_dir}/node/bin/npm"

    if [[ ! -x "$npm_bin" ]]; then
        echo "ERROR: npm not found at ${npm_bin}. Install Node.js first."
        return 1
    fi

    # Can't cache "latest" — always rebuild
    if [[ "$requested_version" != "latest" ]]; then
        local cached_version
        cached_version=$(read_toml_metadata "$toml_file" "claude_code_version")

        if [[ "$cached_version" == "$requested_version" && -d "$layer_dir" ]]; then
            echo "-----> Using cached Claude Code v${requested_version}"
            return 0
        fi
    fi

    echo "-----> Installing Claude Code CLI (${requested_version})"

    rm -rf "$layer_dir"
    mkdir -p "$layer_dir"

    local pkg="@anthropic-ai/claude-code"
    if [[ "$requested_version" != "latest" ]]; then
        pkg="${pkg}@${requested_version}"
    fi

    if ! "$npm_bin" install -g --prefix="$layer_dir" "$pkg" 2>&1; then
        echo "ERROR: Failed to install Claude Code CLI"
        return 1
    fi

    local installed_version
    installed_version=$(get_claude_version "$layers_dir")

    write_layer_toml "$toml_file" "true" "false" "true" \
        "claude_code_version = \"${installed_version}\""

    echo "       Claude Code CLI v${installed_version} installed"
    return 0
}

install_tmux() {
    local layers_dir="$1"
    local layer_dir="${layers_dir}/tmux"
    local toml_file="${layers_dir}/tmux.toml"

    local cached_version
    cached_version=$(read_toml_metadata "$toml_file" "tmux_version")

    if [[ -n "$cached_version" && -x "${layer_dir}/bin/tmux" ]]; then
        echo "-----> Using cached tmux (${cached_version})"
        return 0
    fi

    echo "-----> Setting up tmux layer"

    rm -rf "$layer_dir"
    mkdir -p "${layer_dir}/bin"

    local system_tmux
    system_tmux=$(command -v tmux 2>/dev/null || true)

    if [[ -n "$system_tmux" ]]; then
        cp "$system_tmux" "${layer_dir}/bin/tmux"
        chmod +x "${layer_dir}/bin/tmux"

        local tmux_version
        tmux_version=$("${layer_dir}/bin/tmux" -V 2>/dev/null | awk '{print $2}' || echo "system")

        write_layer_toml "$toml_file" "true" "false" "true" \
            "tmux_version = \"${tmux_version}\""

        echo "       tmux ${tmux_version} installed (from build image)"
    else
        echo "WARNING: tmux not found in build image. tmux will not be available at runtime."
        echo "         To fix: use a builder that includes tmux, or provide a static binary."

        write_layer_toml "$toml_file" "true" "false" "true" \
            "tmux_version = \"unavailable\""
    fi

    return 0
}

get_claude_version() {
    local layers_dir="$1"
    local claude_bin="${layers_dir}/claude-code/bin/claude"

    if [[ -x "$claude_bin" ]]; then
        "$claude_bin" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

verify_installation() {
    local layers_dir="$1"
    local failed=0

    if [[ ! -x "${layers_dir}/node/bin/node" ]]; then
        echo "ERROR: Node.js verification failed — binary not found"
        failed=1
    fi

    if [[ ! -x "${layers_dir}/node/bin/npm" ]]; then
        echo "ERROR: npm verification failed — binary not found"
        failed=1
    fi

    if [[ ! -x "${layers_dir}/claude-code/bin/claude" ]]; then
        echo "ERROR: Claude Code CLI verification failed — binary not found"
        failed=1
    fi

    if [[ $failed -eq 0 ]]; then
        echo "       Installation verified"
    fi

    return $failed
}

cleanup_installation() {
    local layers_dir="$1"

    rm -rf "${layers_dir}/node/include"
    rm -rf "${layers_dir}/node/share/doc"
    rm -rf "${layers_dir}/node/share/man"

    echo "       Cleaned up installation artifacts"
}
