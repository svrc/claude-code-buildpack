#!/usr/bin/env bash
# tests/unit/test_mcp_configurator.sh: Unit tests for lib/claude_configurator.sh (MCP configuration)

set -e

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MCP_LIB="${BP_DIR}/lib/claude_configurator.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source the MCP configurator library
source "${MCP_LIB}"

# Helper functions
print_test_header() {
    echo -e "\n${YELLOW}Running: $1${NC}"
}

assert_success() {
    local test_name=$1
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}: ${test_name}"
}

assert_failure() {
    local test_name=$1
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: ${test_name}"
}

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT

# Test 1: Parse missing config file
print_test_header "Test 1: Parse missing config file"
unset CLAUDE_CODE_CONFIG_FILE
if parse_claude_code_config "${TEST_DIR}"; then
    assert_failure "Should fail when config file doesn't exist"
else
    assert_success "Should fail when config file doesn't exist"
fi

# Test 2: Parse existing config file
print_test_header "Test 2: Parse existing config file"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: filesystem
      type: stdio
      command: npx
EOF

if parse_claude_code_config "${TEST_DIR}"; then
    assert_success "Should find existing .claude-code-config.yml"
else
    assert_failure "Should find existing .claude-code-config.yml"
fi

# Test 3: Generate empty .claude.json when no config exists
print_test_header "Test 3: Generate empty .claude.json when no config exists"
rm -f "${TEST_DIR}/.claude-code-config.yml"
rm -f "${TEST_DIR}/.claude.json"
generate_claude_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude.json" ] && grep -q '"projects"' "${TEST_DIR}/.claude.json" && grep -q '"mcpServers": {}' "${TEST_DIR}/.claude.json"; then
    assert_success "Should create empty .claude.json when no config exists"
else
    assert_failure "Should create empty .claude.json when no config exists"
fi

# Test 4: Generate .claude.json from simple config
print_test_header "Test 4: Generate .claude.json from simple config"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: filesystem
      type: stdio
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-filesystem"
      env:
        ALLOWED_DIRECTORIES: "/workspace,/tmp"
EOF

rm -f "${TEST_DIR}/.claude.json"
generate_claude_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude.json" ]; then
    if grep -q '"filesystem"' "${TEST_DIR}/.claude.json" && \
       grep -q '"type": "stdio"' "${TEST_DIR}/.claude.json" && \
       grep -q '"command": "npx"' "${TEST_DIR}/.claude.json"; then
        assert_success "Should generate .claude.json with filesystem server"
    else
        assert_failure "Should generate .claude.json with filesystem server"
    fi
else
    assert_failure "Should generate .claude.json file"
fi

# Test 5: Generate .claude.json with multiple servers
print_test_header "Test 5: Generate .claude.json with multiple servers"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: filesystem
      type: stdio
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-filesystem"
      env:
        ALLOWED_DIRECTORIES: "/workspace"
    - name: github
      type: stdio
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-github"
      env:
        GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_test123"
EOF

rm -f "${TEST_DIR}/.claude.json"
generate_claude_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude.json" ]; then
    if grep -q '"filesystem"' "${TEST_DIR}/.claude.json" && \
       grep -q '"github"' "${TEST_DIR}/.claude.json"; then
        assert_success "Should generate .claude.json with multiple servers"
    else
        assert_failure "Should generate .claude.json with multiple servers"
    fi
else
    assert_failure "Should generate .claude.json file with multiple servers"
fi

# Test 6: Validate empty .claude.json
print_test_header "Test 6: Validate empty .claude.json"
cat > "${TEST_DIR}/.claude.json" <<'EOF'
{
  "projects": {
    "/workspace": {
      "allowedTools": [],
      "mcpContextUris": [],
      "mcpServers": {},
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": [],
      "hasTrustDialogAccepted": false,
      "projectOnboardingSeenCount": 0,
      "hasClaudeMdExternalIncludesApproved": false,
      "hasClaudeMdExternalIncludesWarningShown": false
    }
  }
}
EOF

if validate_mcp_config "${TEST_DIR}" > /dev/null 2>&1; then
    assert_success "Should validate empty .claude.json"
else
    assert_failure "Should validate empty .claude.json"
fi

# Test 7: Validate .claude.json with servers
print_test_header "Test 7: Validate .claude.json with servers"
cat > "${TEST_DIR}/.claude.json" <<'EOF'
{
  "projects": {
    "/workspace": {
      "allowedTools": [],
      "mcpContextUris": [],
      "mcpServers": {
        "filesystem": {
          "type": "stdio",
          "command": "npx"
        }
      },
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": [],
      "hasTrustDialogAccepted": false,
      "projectOnboardingSeenCount": 0,
      "hasClaudeMdExternalIncludesApproved": false,
      "hasClaudeMdExternalIncludesWarningShown": false
    }
  }
}
EOF

if validate_mcp_config "${TEST_DIR}" > /dev/null 2>&1; then
    assert_success "Should validate .claude.json with servers"
else
    assert_failure "Should validate .claude.json with servers"
fi

# Test 8: Validate missing .claude.json
print_test_header "Test 8: Validate missing .claude.json"
rm -f "${TEST_DIR}/.claude.json"
if validate_mcp_config "${TEST_DIR}" > /dev/null 2>&1; then
    assert_failure "Should fail when .claude.json doesn't exist"
else
    assert_success "Should fail when .claude.json doesn't exist"
fi

# Test 9: Validate malformed .claude.json
print_test_header "Test 9: Validate malformed .claude.json"
cat > "${TEST_DIR}/.claude.json" <<'EOF'
{
  "invalid": "structure"
}
EOF

if validate_mcp_config "${TEST_DIR}" > /dev/null 2>&1; then
    assert_failure "Should fail with malformed .claude.json"
else
    assert_success "Should fail with malformed .claude.json"
fi

# Test 10: Full configure_mcp_servers workflow
print_test_header "Test 10: Full configure_mcp_servers workflow"
rm -f "${TEST_DIR}/.claude.json"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: postgres
      type: stdio
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-postgres"
      env:
        POSTGRES_CONNECTION_STRING: "postgresql://localhost/mydb"
EOF

if configure_mcp_servers "${TEST_DIR}" > /dev/null 2>&1; then
    if [ -f "${TEST_DIR}/.claude.json" ] && grep -q '"postgres"' "${TEST_DIR}/.claude.json"; then
        assert_success "Should complete full MCP configuration workflow"
    else
        assert_failure "Should complete full MCP configuration workflow"
    fi
else
    assert_failure "configure_mcp_servers should succeed"
fi

# Test 10a: configure_claude_settings workflow
print_test_header "Test 10a: configure_claude_settings workflow"
rm -rf "${TEST_DIR}/.claude"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
EOF
parse_claude_code_config "${TEST_DIR}"
if configure_claude_settings "${TEST_DIR}" > /dev/null 2>&1; then
    if [ -f "${TEST_DIR}/.claude/settings.json" ] && grep -q '"alwaysThinkingEnabled": true' "${TEST_DIR}/.claude/settings.json"; then
        assert_success "Should complete Claude settings configuration workflow"
    else
        assert_failure "Should complete Claude settings configuration workflow"
    fi
else
    assert_failure "configure_claude_settings should succeed"
fi

# Test 10b: configure_claude_code workflow (orchestrator)
print_test_header "Test 10b: configure_claude_code workflow"
rm -f "${TEST_DIR}/.claude.json"
rm -rf "${TEST_DIR}/.claude"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
  mcpServers:
    - name: test
      type: stdio
      command: npx
EOF
parse_claude_code_config "${TEST_DIR}"
if configure_claude_code "${TEST_DIR}" > /dev/null 2>&1; then
    if [ -f "${TEST_DIR}/.claude.json" ] && [ -f "${TEST_DIR}/.claude/settings.json" ]; then
        assert_success "Should complete full Claude Code configuration (MCP + settings)"
    else
        assert_failure "Should complete full Claude Code configuration (MCP + settings)"
    fi
else
    assert_failure "configure_claude_code should succeed"
fi

# Test 12: Config file without mcpServers section
print_test_header "Test 12: Config file without mcpServers section"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  version: "2.0.50"
EOF

rm -f "${TEST_DIR}/.claude.json"
OUTPUT_FILE="${TEST_DIR}/.claude.json"
if extract_mcp_servers "${TEST_DIR}/.claude-code-config.yml" "${OUTPUT_FILE}"; then
    assert_failure "Should fail when no mcpServers section exists"
else
    assert_success "Should fail when no mcpServers section exists"
fi

# Test 13: Remote MCP server with SSE transport
print_test_header "Test 13: Remote MCP server with SSE transport"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: remote-sse-server
      type: sse
      url: "https://mcp.example.com/api/sse"
      env:
        API_TOKEN: "test-token-123"
EOF

rm -f "${TEST_DIR}/.claude.json"
generate_claude_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude.json" ] && \
   grep -q '"remote-sse-server"' "${TEST_DIR}/.claude.json" && \
   grep -q '"type": "sse"' "${TEST_DIR}/.claude.json" && \
   grep -q '"url": "https://mcp.example.com/api/sse"' "${TEST_DIR}/.claude.json"; then
    assert_success "Should generate .claude.json with SSE remote server"
else
    assert_failure "Should generate .claude.json with SSE remote server"
fi

# Test 14: Remote MCP server with HTTP transport
print_test_header "Test 14: Remote MCP server with HTTP transport"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: remote-http-server
      type: http
      url: "https://api.example.com/mcp/endpoint"
      env:
        GATEWAY_TOKEN: "Bearer xyz789"
EOF

rm -f "${TEST_DIR}/.claude.json"
generate_claude_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude.json" ] && \
   grep -q '"remote-http-server"' "${TEST_DIR}/.claude.json" && \
   grep -q '"type": "http"' "${TEST_DIR}/.claude.json" && \
   grep -q '"url": "https://api.example.com/mcp/endpoint"' "${TEST_DIR}/.claude.json"; then
    assert_success "Should generate .claude.json with HTTP remote server"
else
    assert_failure "Should generate .claude.json with HTTP remote server"
fi

# Test 15: Parse logLevel from config file
print_test_header "Test 15: Parse logLevel from config file"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  logLevel: debug
EOF

unset CLAUDE_CODE_LOG_LEVEL
parse_config_settings "${TEST_DIR}/.claude-code-config.yml"
if [ "${CLAUDE_CODE_LOG_LEVEL}" = "debug" ]; then
    assert_success "Should parse logLevel setting from config file"
else
    assert_failure "Should parse logLevel setting from config file"
fi

# Test 16: Parse version from config file
print_test_header "Test 16: Parse version from config file"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  version: "2.0.50"
EOF

unset CLAUDE_CODE_VERSION
parse_config_settings "${TEST_DIR}/.claude-code-config.yml"
if [ "${CLAUDE_CODE_VERSION}" = "2.0.50" ]; then
    assert_success "Should parse version setting from config file"
else
    assert_failure "Should parse version setting from config file"
fi

# Test 17: Parse model from config file
print_test_header "Test 17: Parse model from config file"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  model: opus
EOF

unset CLAUDE_CODE_MODEL
parse_config_settings "${TEST_DIR}/.claude-code-config.yml"
if [ "${CLAUDE_CODE_MODEL}" = "opus" ]; then
    assert_success "Should parse model setting from config file"
else
    assert_failure "Should parse model setting from config file"
fi

# Test 18: Parse all settings together
print_test_header "Test 18: Parse all settings together"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  logLevel: warn
  version: "2.1.0"
  model: haiku
EOF

unset CLAUDE_CODE_LOG_LEVEL CLAUDE_CODE_VERSION CLAUDE_CODE_MODEL
parse_config_settings "${TEST_DIR}/.claude-code-config.yml"
if [ "${CLAUDE_CODE_LOG_LEVEL}" = "warn" ] && \
   [ "${CLAUDE_CODE_VERSION}" = "2.1.0" ] && \
   [ "${CLAUDE_CODE_MODEL}" = "haiku" ]; then
    assert_success "Should parse all settings from config file"
else
    assert_failure "Should parse all settings from config file"
fi

# Test 19: Mixed local and remote MCP servers
print_test_header "Test 19: Mixed local and remote MCP servers"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: filesystem
      type: stdio
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-filesystem"
      env:
        ALLOWED_DIRECTORIES: "/tmp"
    - name: remote-data
      type: sse
      url: "https://data.example.com/mcp"
      env:
        DATA_KEY: "abc123"
    - name: llm-gateway
      type: http
      url: "https://llm.example.com/api"
      env:
        LLM_TOKEN: "xyz789"
EOF

rm -f "${TEST_DIR}/.claude.json"
generate_claude_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude.json" ] && \
   grep -q '"filesystem"' "${TEST_DIR}/.claude.json" && \
   grep -q '"remote-data"' "${TEST_DIR}/.claude.json" && \
   grep -q '"llm-gateway"' "${TEST_DIR}/.claude.json" && \
   grep -q '"type": "stdio"' "${TEST_DIR}/.claude.json" && \
   grep -q '"type": "sse"' "${TEST_DIR}/.claude.json" && \
   grep -q '"type": "http"' "${TEST_DIR}/.claude.json"; then
    assert_success "Should generate .claude.json with mixed local and remote servers"
else
    assert_failure "Should generate .claude.json with mixed local and remote servers"
fi

# Test 20: Generate settings.json with default configuration
print_test_header "Test 20: Generate settings.json with default configuration"
rm -rf "${TEST_DIR}/.claude"
rm -f "${TEST_DIR}/.claude-code-config.yml"
generate_claude_settings_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude/settings.json" ] && grep -q '"alwaysThinkingEnabled": true' "${TEST_DIR}/.claude/settings.json"; then
    assert_success "Should create default settings.json with alwaysThinkingEnabled: true"
else
    assert_failure "Should create default settings.json with alwaysThinkingEnabled: true"
fi

# Test 21: Generate settings.json from config with alwaysThinkingEnabled: true
print_test_header "Test 21: Generate settings.json from config with alwaysThinkingEnabled: true"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
  mcpServers: []
EOF
rm -rf "${TEST_DIR}/.claude"
parse_claude_code_config "${TEST_DIR}"
generate_claude_settings_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude/settings.json" ] && grep -q '"alwaysThinkingEnabled": true' "${TEST_DIR}/.claude/settings.json"; then
    assert_success "Should create settings.json with alwaysThinkingEnabled: true from config"
else
    assert_failure "Should create settings.json with alwaysThinkingEnabled: true from config"
fi

# Test 22: Generate settings.json from config with alwaysThinkingEnabled: false
print_test_header "Test 22: Generate settings.json from config with alwaysThinkingEnabled: false"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: false
  mcpServers: []
EOF
rm -rf "${TEST_DIR}/.claude"
parse_claude_code_config "${TEST_DIR}"
generate_claude_settings_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude/settings.json" ] && grep -q '"alwaysThinkingEnabled": false' "${TEST_DIR}/.claude/settings.json"; then
    assert_success "Should create settings.json with alwaysThinkingEnabled: false from config"
else
    assert_failure "Should create settings.json with alwaysThinkingEnabled: false from config"
fi

# Test 23: Verify settings.json is valid JSON
print_test_header "Test 23: Verify settings.json is valid JSON"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
EOF
rm -rf "${TEST_DIR}/.claude"
parse_claude_code_config "${TEST_DIR}"
generate_claude_settings_json "${TEST_DIR}"
if command -v python3 > /dev/null 2>&1; then
    if python3 -c "import json; json.load(open('${TEST_DIR}/.claude/settings.json'))" 2>/dev/null; then
        assert_success "settings.json should be valid JSON"
    else
        assert_failure "settings.json should be valid JSON"
    fi
else
    assert_success "Python3 not available, skipping JSON validation"
fi

# Test 24: Generate settings.json without settings section in config
print_test_header "Test 24: Generate settings.json without settings section in config"
cat > "${TEST_DIR}/.claude-code-config.yml" <<'EOF'
claudeCode:
  enabled: true
  mcpServers:
    - name: github
      type: sse
      url: "https://github-mcp.example.com/sse"
EOF
rm -rf "${TEST_DIR}/.claude"
parse_claude_code_config "${TEST_DIR}"
generate_claude_settings_json "${TEST_DIR}"
if [ -f "${TEST_DIR}/.claude/settings.json" ] && grep -q '"alwaysThinkingEnabled": true' "${TEST_DIR}/.claude/settings.json"; then
    assert_success "Should create default settings.json when settings section is missing"
else
    assert_failure "Should create default settings.json when settings section is missing"
fi

# ============================================================================
# Deny List Tests
# ============================================================================

# Test: Parse settings with deny list (permission-based)
print_test_header "Test: Parse settings with deny list (permission-based)"
cat > "${TEST_DIR}/.claude-code-config-deny.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
    permissions:
      deny:
        - "Bash(curl:*)"
        - "Bash(npm run deploy)"
        - "Read(./.env)"
        - "Read(./secrets/**)"
        - "WebFetch"
EOF

output_file="${TEST_DIR}/.claude-settings-test.json"
if parse_settings_from_yaml "${TEST_DIR}/.claude-code-config-deny.yml" "${output_file}"; then
    if [ -f "${output_file}" ] && \
       grep -q '"alwaysThinkingEnabled": true' "${output_file}" && \
       grep -q '"permissions"' "${output_file}" && \
       grep -q '"deny"' "${output_file}" && \
       grep -q '"Bash(curl:\*)"' "${output_file}" && \
       grep -q '"WebFetch"' "${output_file}"; then
        assert_success "Should parse settings with deny list"
    else
        echo "Generated settings.json:"
        cat "${output_file}"
        assert_failure "Should parse settings with deny list"
    fi
else
    assert_failure "Should parse settings with deny list"
fi

# Test: Parse settings with MCP tool denials
print_test_header "Test: Parse settings with MCP tool denials"
cat > "${TEST_DIR}/.claude-code-config-mcp-deny.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
    permissions:
      deny:
        - "mcp__github__create_issue"
        - "mcp__github__delete_repository"
        - "mcp__filesystem__write_file"
EOF

output_file2="${TEST_DIR}/.claude-settings-mcp-test.json"
if parse_settings_from_yaml "${TEST_DIR}/.claude-code-config-mcp-deny.yml" "${output_file2}"; then
    if [ -f "${output_file2}" ] && \
       grep -q '"mcp__github__create_issue"' "${output_file2}" && \
       grep -q '"mcp__filesystem__write_file"' "${output_file2}"; then
        assert_success "Should parse settings with MCP tool denials"
    else
        echo "Generated settings.json:"
        cat "${output_file2}"
        assert_failure "Should parse settings with MCP tool denials"
    fi
else
    assert_failure "Should parse settings with MCP tool denials"
fi

# Test: Parse settings with mixed denials
print_test_header "Test: Parse settings with mixed denials (permission + MCP)"
cat > "${TEST_DIR}/.claude-code-config-mixed-deny.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: false
    permissions:
      deny:
        - "Bash(curl:*)"
        - "WebFetch"
        - "mcp__github__create_issue"
        - "mcp__filesystem__write_file"
        - "Read(./.env)"
EOF

output_file3="${TEST_DIR}/.claude-settings-mixed-test.json"
if parse_settings_from_yaml "${TEST_DIR}/.claude-code-config-mixed-deny.yml" "${output_file3}"; then
    if [ -f "${output_file3}" ] && \
       grep -q '"alwaysThinkingEnabled": false' "${output_file3}" && \
       grep -q '"Bash(curl:\*)"' "${output_file3}" && \
       grep -q '"WebFetch"' "${output_file3}" && \
       grep -q '"mcp__github__create_issue"' "${output_file3}" && \
       grep -q '"Read(./.env)"' "${output_file3}"; then
        # Verify we have 5 deny rules
        deny_count=$(grep -o '"Bash\|"WebFetch\|"mcp__\|"Read' "${output_file3}" | wc -l)
        if [ "${deny_count}" -ge 5 ]; then
            assert_success "Should parse settings with mixed denials"
        else
            echo "Expected 5 deny rules, found ${deny_count}"
            cat "${output_file3}"
            assert_failure "Should parse settings with mixed denials"
        fi
    else
        echo "Generated settings.json:"
        cat "${output_file3}"
        assert_failure "Should parse settings with mixed denials"
    fi
else
    assert_failure "Should parse settings with mixed denials"
fi

# Test: Parse settings without deny list
print_test_header "Test: Parse settings without deny list"
cat > "${TEST_DIR}/.claude-code-config-no-deny.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
EOF

output_file4="${TEST_DIR}/.claude-settings-no-deny-test.json"
if parse_settings_from_yaml "${TEST_DIR}/.claude-code-config-no-deny.yml" "${output_file4}"; then
    if [ -f "${output_file4}" ] && \
       grep -q '"alwaysThinkingEnabled": true' "${output_file4}" && \
       ! grep -q '"permissions"' "${output_file4}"; then
        assert_success "Should parse settings without deny list (no permissions key)"
    else
        echo "Generated settings.json:"
        cat "${output_file4}"
        assert_failure "Should parse settings without deny list (no permissions key)"
    fi
else
    assert_failure "Should parse settings without deny list"
fi

# Test: Generate settings.json with deny rules
print_test_header "Test: Generate settings.json with deny rules"
cat > "${TEST_DIR}/.claude-code-config-full.yml" <<'EOF'
claudeCode:
  enabled: true
  logLevel: debug
  settings:
    alwaysThinkingEnabled: true
    permissions:
      deny:
        - "Bash(curl:*)"
        - "WebFetch"
        - "mcp__github__create_issue"
EOF

export CLAUDE_CODE_CONFIG_FILE="${TEST_DIR}/.claude-code-config-full.yml"
rm -rf "${TEST_DIR}/.claude"
generate_claude_settings_json "${TEST_DIR}"

settings_file="${TEST_DIR}/.claude/settings.json"
if [ -f "${settings_file}" ] && \
   grep -q '"alwaysThinkingEnabled": true' "${settings_file}" && \
   grep -q '"permissions"' "${settings_file}" && \
   grep -q '"deny"' "${settings_file}" && \
   grep -q '"Bash(curl:\*)"' "${settings_file}" && \
   grep -q '"mcp__github__create_issue"' "${settings_file}"; then
    assert_success "Should generate settings.json with deny rules"
else
    echo "Generated settings.json:"
    [ -f "${settings_file}" ] && cat "${settings_file}" || echo "File not found"
    assert_failure "Should generate settings.json with deny rules"
fi

# Test: Generate default settings.json without configuration
print_test_header "Test: Generate default settings.json without deny configuration"
rm -f "${TEST_DIR}/.claude-code-config-full.yml"
rm -rf "${TEST_DIR}/.claude"
unset CLAUDE_CODE_CONFIG_FILE
generate_claude_settings_json "${TEST_DIR}"

settings_file2="${TEST_DIR}/.claude/settings.json"
if [ -f "${settings_file2}" ] && \
   grep -q '"alwaysThinkingEnabled": true' "${settings_file2}" && \
   ! grep -q '"permissions"' "${settings_file2}"; then
    assert_success "Should generate default settings.json without permissions"
else
    echo "Generated settings.json:"
    [ -f "${settings_file2}" ] && cat "${settings_file2}" || echo "File not found"
    assert_failure "Should generate default settings.json without permissions"
fi

# Test: Handle empty deny list
print_test_header "Test: Handle empty deny list"
cat > "${TEST_DIR}/.claude-code-config-empty-deny.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
    permissions:
      deny:
EOF

output_file5="${TEST_DIR}/.claude-settings-empty-deny-test.json"
if parse_settings_from_yaml "${TEST_DIR}/.claude-code-config-empty-deny.yml" "${output_file5}"; then
    if [ -f "${output_file5}" ] && \
       grep -q '"alwaysThinkingEnabled": true' "${output_file5}"; then
        # Empty deny list should not add permissions key
        if ! grep -q '"permissions"' "${output_file5}"; then
            assert_success "Should handle empty deny list (no permissions key)"
        else
            # OR it could have empty array - both are acceptable
            if grep -q '"deny": \[\]' "${output_file5}"; then
                assert_success "Should handle empty deny list (empty array)"
            else
                echo "Generated settings.json:"
                cat "${output_file5}"
                assert_failure "Should handle empty deny list correctly"
            fi
        fi
    else
        echo "Generated settings.json:"
        cat "${output_file5}"
        assert_failure "Should handle empty deny list"
    fi
else
    assert_failure "Should handle empty deny list"
fi

# Test: Parse deny list with inline comments
print_test_header "Test: Parse deny list with inline comments"
cat > "${TEST_DIR}/.claude-code-config-comments.yml" <<'EOF'
claudeCode:
  enabled: true
  settings:
    alwaysThinkingEnabled: true
    permissions:
      deny:
        # Block specific MCP tools
        - "mcp__github__create_issue"        # Block GitHub issue creation
        - "mcp__github__delete_repository"   # Block repo deletion
        - "Bash(curl:*)"  # Block curl
EOF

output_file6="${TEST_DIR}/.claude-settings-comments-test.json"
if parse_settings_from_yaml "${TEST_DIR}/.claude-code-config-comments.yml" "${output_file6}"; then
    if [ -f "${output_file6}" ]; then
        # Verify no comments are included in the deny items
        if grep -q '# Block' "${output_file6}"; then
            echo "Generated settings.json contains comments:"
            cat "${output_file6}"
            assert_failure "Should strip inline comments from deny items"
        elif grep -q '"mcp__github__create_issue"' "${output_file6}" && \
             grep -q '"mcp__github__delete_repository"' "${output_file6}" && \
             grep -q '"Bash(curl:\*)"' "${output_file6}"; then
            assert_success "Should parse deny list with inline comments"
        else
            echo "Generated settings.json missing expected items:"
            cat "${output_file6}"
            assert_failure "Should parse deny list with inline comments"
        fi
    else
        assert_failure "Should create output file"
    fi
else
    assert_failure "Should parse deny list with inline comments"
fi

# Print summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Total tests run: ${TESTS_RUN}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo "======================================"

if [ ${TESTS_FAILED} -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
