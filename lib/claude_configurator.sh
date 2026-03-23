#!/usr/bin/env bash
# lib/mcp_configurator.sh: Claude Code configuration management
# Handles both MCP server configuration and Claude settings generation

# Parse Claude Code configuration settings from .claude-code-config.yml
# Extracts logLevel, version, model, etc.
parse_config_settings() {
    local config_file=$1

    if [ ! -f "${config_file}" ]; then
        return 1
    fi

    # Parse logLevel setting
    local log_level=$(grep -E "^[[:space:]]*logLevel:" "${config_file}" | sed -E 's/^[[:space:]]*logLevel:[[:space:]]*(.+)[[:space:]]*$/\1/' | tr -d '"' | tr -d "'")
    if [ -n "${log_level}" ]; then
        export CLAUDE_CODE_LOG_LEVEL="${log_level}"
        echo "       Setting log level: ${log_level}"
    fi

    # Parse version setting
    local version=$(grep -E "^[[:space:]]*version:" "${config_file}" | sed -E 's/^[[:space:]]*version:[[:space:]]*(.+)[[:space:]]*$/\1/' | tr -d '"' | tr -d "'")
    if [ -n "${version}" ]; then
        export CLAUDE_CODE_VERSION="${version}"
        echo "       Setting Claude Code version: ${version}"
    fi

    # Parse model setting
    local model=$(grep -E "^[[:space:]]*model:" "${config_file}" | sed -E 's/^[[:space:]]*model:[[:space:]]*(.+)[[:space:]]*$/\1/' | tr -d '"' | tr -d "'")
    if [ -n "${model}" ]; then
        export CLAUDE_CODE_MODEL="${model}"
        echo "       Setting Claude Code model: ${model}"
    fi

    return 0
}

# Parse MCP server configuration from .claude-code-config.yml
# Returns 0 if configuration found, 1 otherwise
parse_claude_code_config() {
    local build_dir=$1
    local config_file="${build_dir}/.claude-code-config.yml"

    if [ ! -f "${config_file}" ]; then
        return 1
    fi

    echo "       Found .claude-code-config.yml configuration file"

    # Parse configuration settings (logLevel, version, model)
    parse_config_settings "${config_file}"

    # Export config file location for later parsing
    export CLAUDE_CODE_CONFIG_FILE="${config_file}"
    return 0
}

# Extract MCP servers from YAML configuration file
# Simplified YAML parser for the specific structure we expect
extract_mcp_servers() {
    local config_file=$1
    local output_file=$2

    if [ ! -f "${config_file}" ]; then
        echo "       No configuration file found: ${config_file}"
        return 1
    fi

    # Parse YAML and convert to JSON
    # This is a simplified parser that handles the specific structure in DESIGN.md

    # Check if file has mcpServers or mcp-servers section
    if ! grep -qE "(mcpServers|mcp-servers):" "${config_file}"; then
        echo "       No MCP server configuration found in ${config_file}"
        return 1
    fi

    # Use Python for YAML parsing (available in Cloud Foundry stacks)
    if command -v python3 > /dev/null 2>&1; then
        # Run Python parser - stdout goes to file, stderr goes to console
        python3 - "${config_file}" > "${output_file}" <<'PYTHON_SCRIPT'
import sys
import re
import json

if len(sys.argv) < 2:
    sys.exit(1)

config_file = sys.argv[1]

try:
    with open(config_file, 'r') as f:
        lines = f.readlines()
except Exception as e:
    # Return empty config with projects structure
    print(json.dumps({
        'projects': {
            '/workspace': {
                'allowedTools': [],
                'mcpContextUris': [],
                'mcpServers': {},
                'enabledMcpjsonServers': [],
                'disabledMcpjsonServers': [],
                'hasTrustDialogAccepted': False,
                'projectOnboardingSeenCount': 0,
                'hasClaudeMdExternalIncludesApproved': False,
                'hasClaudeMdExternalIncludesWarningShown': False
            }
        }
    }))
    sys.exit(0)

mcp_servers = {}
in_mcp = False
current_server = None
current_server_name = None
in_args = False
in_env = False

for line in lines:
    stripped = line.strip()

    # Detect start of mcpServers or mcp-servers section
    if re.match(r'(mcpServers|mcp-servers):', stripped):
        in_mcp = True
        continue

    # Detect start of new server (with or without inline name)
    if in_mcp and re.match(r'-\s+name:', stripped):
        # Save previous server
        if current_server and current_server_name:
            mcp_servers[current_server_name] = current_server

        # Start new server
        match = re.search(r'name:\s*(.+)', stripped)
        current_server_name = match.group(1).strip() if match else None
        current_server = {}
        in_args = False
        in_env = False
        continue

    # Parse server properties (only when we have a current server)
    if current_server is not None:
        # Type (stdio, sse, http)
        if re.match(r'^\s*type:', line):
            match = re.search(r'type:\s*(.+)', stripped)
            if match:
                current_server['type'] = match.group(1).strip()

        # URL (for remote servers: sse, http)
        elif re.match(r'^\s*url:', line):
            match = re.search(r'url:\s*(.+)', stripped)
            if match:
                url = match.group(1).strip().strip('"')
                current_server['url'] = url

        # Command (for local servers: stdio)
        elif re.match(r'^\s*command:', line):
            match = re.search(r'command:\s*(.+)', stripped)
            if match:
                current_server['command'] = match.group(1).strip()

        # Args array
        elif re.match(r'^\s*args:', line):
            current_server['args'] = []
            in_args = True
            in_env = False

        elif in_args:
            if re.match(r'^\s+-\s+"', line):
                match = re.search(r'-\s+"([^"]+)"', stripped)
                if match:
                    current_server['args'].append(match.group(1))
            elif re.match(r'^\s*[a-zA-Z_]+:', line):
                # Exit args section
                in_args = False

        # Env object
        if re.match(r'^\s*env:', line) and not in_args:
            current_server['env'] = {}
            in_env = True
            in_args = False

        elif in_env and re.match(r'^\s+[A-Z_]+:', line):
            match = re.search(r'([A-Z_]+):\s*(.+)', stripped)
            if match:
                key = match.group(1).strip()
                value = match.group(2).strip().strip('"').strip("'")
                # Handle environment variable substitution syntax
                current_server['env'][key] = value

    # Detect end of MCP section
    # Exit if we hit a non-indented, non-empty line that's not a comment and not a dash
    if in_mcp and line and not line.startswith((' ', '\t', '-', '#')) and stripped:
        in_mcp = False

# Add last server
if current_server and current_server_name:
    mcp_servers[current_server_name] = current_server

# Output JSON in Claude Code format with projects structure
# The app directory is /workspace in Cloud Foundry
output = {
    'projects': {
        '/workspace': {
            'allowedTools': [],
            'mcpContextUris': [],
            'mcpServers': mcp_servers,
            'enabledMcpjsonServers': [],
            'disabledMcpjsonServers': [],
            'hasTrustDialogAccepted': False,
            'projectOnboardingSeenCount': 0,
            'hasClaudeMdExternalIncludesApproved': False,
            'hasClaudeMdExternalIncludesWarningShown': False
        }
    }
}
print(json.dumps(output, indent=2))
PYTHON_SCRIPT

    else
        # Fallback: create empty config if Python not available
        cat > "${output_file}" <<'EOF'
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
        echo "       WARNING: Python3 not available for YAML parsing, using empty config"
        return 1
    fi

    # Validate generated JSON
    if [ -f "${output_file}" ]; then
        # Basic validation - check if file has proper structure
        if grep -q '"projects"' "${output_file}" && grep -q '"mcpServers"' "${output_file}"; then
            echo "       Generated .claude.json with MCP server configuration"
            return 0
        fi
    fi

    echo "       Failed to generate valid .claude.json"
    return 1
}

# Generate .claude.json configuration file with MCP servers under projects section
# Note: Claude Code uses .claude.json with a projects structure for MCP server configuration
generate_claude_json() {
    local build_dir=$1
    local output_file="${build_dir}/.claude.json"
    
    # Try to parse .claude-code-config.yml first
    if parse_claude_code_config "${build_dir}"; then
        if extract_mcp_servers "${CLAUDE_CODE_CONFIG_FILE}" "${output_file}"; then
            echo "       Created .claude.json from .claude-code-config.yml"
            return 0
        fi
    fi

    # No configuration found - create empty .claude.json with projects structure
    cat > "${output_file}" <<'EOF'
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

    echo "       Created empty .claude.json (no MCP configuration found)"
    return 0
}

# Parse settings section from YAML configuration
# Extracts alwaysThinkingEnabled and permissions.deny array
parse_settings_from_yaml() {
    local config_file=$1
    local output_file=$2

    if [ ! -f "${config_file}" ]; then
        return 1
    fi

    # Check if settings section exists
    if ! grep -q "^\s*settings:" "${config_file}"; then
        return 1
    fi

    # Use Python for YAML parsing
    if command -v python3 > /dev/null 2>&1; then
        python3 - "${config_file}" > "${output_file}" 2>&1 <<'PYTHON_SCRIPT'
import sys
import re
import json

if len(sys.argv) < 2:
    sys.exit(1)

config_file = sys.argv[1]

try:
    with open(config_file, 'r') as f:
        lines = f.readlines()
except Exception as e:
    # Return default settings
    print(json.dumps({"alwaysThinkingEnabled": True}), file=sys.stdout)
    sys.exit(0)

settings = {
    "alwaysThinkingEnabled": True  # Default value
}
in_settings = False
in_permissions = False
in_deny = False
deny_list = []

for i, line in enumerate(lines):
    stripped = line.strip()

    # Detect start of settings section
    if re.match(r'settings:', stripped):
        in_settings = True
        continue

    # Exit settings section if we hit a non-indented, non-comment line
    if in_settings and line and not line.startswith((' ', '\t', '-', '#')) and stripped:
        in_settings = False
        break

    if in_settings:
        # Parse alwaysThinkingEnabled
        if re.match(r'alwaysThinkingEnabled:', stripped):
            match = re.search(r'alwaysThinkingEnabled:\s*(true|false)', stripped)
            if match:
                settings['alwaysThinkingEnabled'] = match.group(1) == 'true'

        # Detect permissions section
        if re.match(r'permissions:', stripped):
            in_permissions = True
            continue

        # Detect deny array within permissions
        if in_permissions and re.match(r'deny:', stripped):
            in_deny = True
            continue

        # Parse deny list items
        if in_deny and re.match(r'-\s+', stripped):
            # Extract the deny item, handling quotes and comments
            # Format: - "item" # comment  OR  - item # comment
            match = re.search(r'-\s+(["\']?)(.+?)\1(?:\s*#.*)?$', stripped)
            if match:
                deny_item = match.group(2).strip()
                # Remove any trailing comments that weren't caught by regex
                if '#' in deny_item and not deny_item.startswith('#'):
                    # Find the last quote (if any) before the comment
                    quote_pos = max(deny_item.rfind('"'), deny_item.rfind("'"))
                    hash_pos = deny_item.find('#')
                    # Only strip comment if it's after any quotes
                    if hash_pos > quote_pos:
                        deny_item = deny_item[:hash_pos].strip()
                deny_list.append(deny_item)

        # Exit deny section if we hit a non-list-item line
        if in_deny and not re.match(r'-\s+', stripped) and stripped and not stripped.startswith('#'):
            in_deny = False

# Add permissions.deny to settings if we found deny rules
if deny_list:
    settings['permissions'] = {
        'deny': deny_list
    }

# Output JSON
print(json.dumps(settings, indent=2), file=sys.stdout)
PYTHON_SCRIPT

        if [ $? -eq 0 ]; then
            return 0
        else
            return 1
        fi
    else
        # Fallback: create default settings if Python not available
        echo '{"alwaysThinkingEnabled": true}' > "${output_file}"
        return 1
    fi
}

# Generate .claude/settings.json from configuration
# This creates Claude Code settings like alwaysThinkingEnabled and permissions.deny
generate_claude_settings_json() {
    local build_dir=$1
    local settings_dir="${build_dir}/.claude"
    local settings_file="${settings_dir}/settings.json"

    # Create .claude directory if it doesn't exist
    mkdir -p "${settings_dir}"

    echo "-----> Generating Claude settings configuration"

    # Check if config file specifies settings
    if [ -n "${CLAUDE_CODE_CONFIG_FILE}" ] && [ -f "${CLAUDE_CODE_CONFIG_FILE}" ]; then
        # Check if settings section exists
        if grep -q "^\s*settings:" "${CLAUDE_CODE_CONFIG_FILE}"; then
            echo "       Parsing settings from configuration file..."

            # Parse settings using Python
            local temp_settings="${build_dir}/.claude-settings-temp.json"
            if parse_settings_from_yaml "${CLAUDE_CODE_CONFIG_FILE}" "${temp_settings}"; then
                # Check if we got valid JSON
                if [ -f "${temp_settings}" ] && grep -q '"alwaysThinkingEnabled"' "${temp_settings}"; then
                    mv "${temp_settings}" "${settings_file}"
                    echo "       Created ${settings_file} from configuration"

                    # Log what was configured
                    if grep -q '"permissions"' "${settings_file}"; then
                        # Use Python to accurately count deny rules
                        local deny_count=$(python3 -c "import json; data=json.load(open('${settings_file}')); print(len(data.get('permissions', {}).get('deny', [])))" 2>/dev/null || echo "0")
                        if [ "${deny_count}" -gt 0 ]; then
                            echo "       Configured ${deny_count} deny rule(s)"
                        fi
                    fi

                    return 0
                fi
            fi

            # Clean up temp file if it exists
            rm -f "${temp_settings}"
        fi
    fi

    # If no settings specified, create default with alwaysThinkingEnabled: true
    # This improves multi-step operation performance in Cloud Foundry
    echo "       Using default settings with extended thinking enabled"
    cat > "${settings_file}" <<'EOF'
{
  "alwaysThinkingEnabled": true
}
EOF

    echo "       Created ${settings_file} with default configuration"
    return 0
}

# Validate MCP server configuration in .claude.json
validate_mcp_config() {
    local build_dir=$1
    local config_file="${build_dir}/.claude.json"

    if [ ! -f "${config_file}" ]; then
        echo "       WARNING: .claude.json not found"
        return 1
    fi

    # Basic validation - check JSON structure
    if ! grep -q '"projects"' "${config_file}" || ! grep -q '"mcpServers"' "${config_file}"; then
        echo "       WARNING: .claude.json missing projects or mcpServers section"
        return 1
    fi

    # Check if mcpServers has any servers configured
    # Note: grep -c outputs "0" even when no matches are found, so we don't need || echo "0"
    local server_count=$(grep -c '"type"' "${config_file}" 2>/dev/null || true)

    if [ "${server_count}" -eq 0 ] 2>/dev/null; then
        echo "       No MCP servers configured (using empty configuration)"
    else
        echo "       Validated .claude.json with ${server_count} MCP server(s)"
    fi

    return 0
}

# Generate MCP server configuration (.claude.json)
configure_mcp_servers() {
    local build_dir=$1

    echo "-----> Configuring MCP servers"

    # Generate .claude.json
    if ! generate_claude_json "${build_dir}"; then
        echo "       WARNING: Failed to generate .claude.json, using empty configuration"
    fi

    # Validate configuration
    validate_mcp_config "${build_dir}"

    return 0
}

# Generate Claude settings configuration (.claude/settings.json)
configure_claude_settings() {
    local build_dir=$1

    echo "-----> Configuring Claude settings"

    # Generate .claude/settings.json
    generate_claude_settings_json "${build_dir}"

    return 0
}

# Main configuration function - configures both MCP servers and Claude settings
configure_claude_code() {
    local build_dir=$1

    # Configure MCP servers (.claude.json)
    configure_mcp_servers "${build_dir}"

    # Configure Claude settings (.claude/settings.json)
    configure_claude_settings "${build_dir}"

    return 0
}

# ============================================================================
# Skills Configuration Functions
# ============================================================================

# Validate Skill structure
# Verifies SKILL.md exists and has proper frontmatter
validate_skill_structure() {
    local skill_dir=$1
    local skill_name=$(basename "${skill_dir}")
    
    # Check if SKILL.md exists
    if [ ! -f "${skill_dir}/SKILL.md" ]; then
        echo "       WARNING: Skill missing SKILL.md: ${skill_name}" >&2
        return 1
    fi
    
    # Check for YAML frontmatter
    if ! head -1 "${skill_dir}/SKILL.md" | grep -q "^---"; then
        echo "       WARNING: SKILL.md missing YAML frontmatter: ${skill_name}" >&2
        return 1
    fi
    
    # Extract and validate frontmatter fields
    local has_name=false
    local has_description=false
    
    # Read first 20 lines to check frontmatter
    while IFS= read -r line; do
        if echo "${line}" | grep -q "^name:"; then
            has_name=true
        fi
        if echo "${line}" | grep -q "^description:"; then
            has_description=true
        fi
        # Stop at closing ---
        if echo "${line}" | grep -q "^---" && [ "${has_name}" = true ]; then
            break
        fi
    done < <(head -20 "${skill_dir}/SKILL.md" | tail -n +2)
    
    if [ "${has_name}" = false ]; then
        echo "       WARNING: SKILL.md missing 'name' field: ${skill_name}" >&2
        return 1
    fi
    
    if [ "${has_description}" = false ]; then
        echo "       WARNING: SKILL.md missing 'description' field: ${skill_name}" >&2
        return 1
    fi
    
    return 0
}

# List installed Skills for debugging
list_installed_skills() {
    local skills_dir=$1
    
    if [ ! -d "${skills_dir}" ]; then
        echo "       No Skills directory found"
        return 0
    fi
    
    local skill_count=0
    for skill_dir in "${skills_dir}"/*; do
        if [ -d "${skill_dir}" ] && [ -f "${skill_dir}/SKILL.md" ]; then
            skill_count=$((skill_count + 1))
            local skill_name=$(basename "${skill_dir}")
            echo "       - ${skill_name}"
        fi
    done
    
    if [ ${skill_count} -eq 0 ]; then
        echo "       No Skills found"
    else
        echo "       Total Skills: ${skill_count}"
    fi
    
    return 0
}

# Main Skills configuration function
configure_skills() {
    local build_dir=$1
    local cache_dir=$2

    echo "-----> Configuring Claude Skills"

    # Create Skills directory
    local skills_dir="${build_dir}/.claude/skills"
    mkdir -p "${skills_dir}"

    # Check for bundled Skills (already in .claude/skills/)
    local bundled_count=0
    if [ -d "${skills_dir}" ]; then
        for skill_dir in "${skills_dir}"/*; do
            if [ -d "${skill_dir}" ] && [ -f "${skill_dir}/SKILL.md" ]; then
                bundled_count=$((bundled_count + 1))
            fi
        done
    fi

    if [ ${bundled_count} -gt 0 ]; then
        echo "       Found ${bundled_count} bundled Skill(s)"
    else
        echo "       No bundled Skills found"
    fi

    # Validate all Skills
    echo "       Validating Skills..."
    local valid_count=0
    local invalid_count=0

    for skill_dir in "${skills_dir}"/*; do
        if [ -d "${skill_dir}" ]; then
            if validate_skill_structure "${skill_dir}"; then
                valid_count=$((valid_count + 1))
            else
                invalid_count=$((invalid_count + 1))
            fi
        fi
    done

    echo "       Valid Skills: ${valid_count}"
    if [ ${invalid_count} -gt 0 ]; then
        echo "       Invalid Skills: ${invalid_count} (see warnings above)"
    fi

    # List installed Skills
    echo "       Installed Skills:"
    list_installed_skills "${skills_dir}"

    return 0
}

# ============================================================================
# Plugin Marketplace Configuration Functions
# ============================================================================

# Parse plugin marketplaces from YAML configuration file
# Outputs JSON array of marketplace configurations to stdout
# Usage: parse_plugin_marketplaces config_file output_file
parse_plugin_marketplaces() {
    local config_file=$1
    local output_file=$2

    if [ ! -f "${config_file}" ]; then
        echo "[]" > "${output_file}"
        return 1
    fi

    # Check if file has pluginMarketplaces section
    if ! grep -qE "pluginMarketplaces:" "${config_file}"; then
        echo "[]" > "${output_file}"
        return 1
    fi

    # Use Python for YAML parsing
    if command -v python3 > /dev/null 2>&1; then
        python3 - "${config_file}" > "${output_file}" 2>/dev/null <<'PYTHON_SCRIPT'
import sys
import re
import json

if len(sys.argv) < 2:
    print("[]")
    sys.exit(0)

config_file = sys.argv[1]

try:
    with open(config_file, 'r') as f:
        lines = f.readlines()
except Exception as e:
    print("[]")
    sys.exit(0)

marketplaces = []
in_marketplaces = False
current_marketplace = None
in_plugins = False
marketplaces_indent = 0  # Track indentation level of pluginMarketplaces section

def get_indent(line):
    """Get the indentation level of a line (number of leading spaces/tabs)."""
    return len(line) - len(line.lstrip())

for line in lines:
    stripped = line.strip()
    
    # Skip empty lines and comments
    if not stripped or stripped.startswith('#'):
        continue
    
    # Detect start of pluginMarketplaces section
    if re.match(r'pluginMarketplaces:', stripped):
        in_marketplaces = True
        marketplaces_indent = get_indent(line)
        continue
    
    # Exit marketplaces section if we hit another key at the same or lower indentation level
    # This handles keys like mcpServers: that are siblings of pluginMarketplaces:
    if in_marketplaces:
        current_indent = get_indent(line)
        # Check if this is a YAML key (contains colon) at same/lower indentation as pluginMarketplaces
        if current_indent <= marketplaces_indent and re.match(r'\w+:', stripped) and not stripped.startswith('-'):
            in_marketplaces = False
            # Save last marketplace
            if current_marketplace and current_marketplace.get('name'):
                marketplaces.append(current_marketplace)
                current_marketplace = None
            # Don't break - continue processing other sections
            continue
    
    if in_marketplaces:
        # Detect start of new marketplace entry (- name: ...)
        if re.match(r'-\s+name:', stripped):
            # Save previous marketplace
            if current_marketplace and current_marketplace.get('name'):
                marketplaces.append(current_marketplace)
            
            # Start new marketplace
            match = re.search(r'name:\s*(.+)', stripped)
            current_marketplace = {
                'name': match.group(1).strip().strip('"').strip("'") if match else None,
                'source': None,
                'branch': 'main',
                'plugins': []
            }
            in_plugins = False
            continue
        
        # Parse marketplace properties
        if current_marketplace is not None:
            # Source (git URL)
            if re.match(r'^\s+source:', line):
                match = re.search(r'source:\s*(.+)', stripped)
                if match:
                    current_marketplace['source'] = match.group(1).strip().strip('"').strip("'")
            
            # Branch
            elif re.match(r'^\s+branch:', line):
                match = re.search(r'branch:\s*(.+)', stripped)
                if match:
                    current_marketplace['branch'] = match.group(1).strip().strip('"').strip("'")
            
            # Plugins array
            elif re.match(r'^\s+plugins:', line):
                in_plugins = True
                continue
            
            # Plugin list items (check for lines that start with whitespace + dash)
            elif in_plugins and re.match(r'^\s+-', line) and not stripped.startswith('- name:'):
                match = re.search(r'-\s+(.+)', stripped)
                if match:
                    plugin_name = match.group(1).strip().strip('"').strip("'")
                    current_marketplace['plugins'].append(plugin_name)
            
            # Exit plugins section if we hit a non-list line (indented but not a dash)
            elif in_plugins and not re.match(r'^\s+-', line) and stripped:
                in_plugins = False

# Add last marketplace
if current_marketplace and current_marketplace.get('name'):
    marketplaces.append(current_marketplace)

print(json.dumps(marketplaces, indent=2))
PYTHON_SCRIPT

        if [ $? -eq 0 ] && [ -s "${output_file}" ]; then
            return 0
        fi
    fi

    # Fallback: return empty array
    echo "[]" > "${output_file}"
    return 1
}

# Clone a git marketplace repository
# Usage: clone_marketplace source branch target_dir
# Returns: 0 on success, 1 on failure
clone_marketplace() {
    local source=$1
    local branch=$2
    local target_dir=$3
    
    if [ -z "${source}" ] || [ -z "${target_dir}" ]; then
        echo "       ERROR: Missing source or target directory for marketplace clone" >&2
        return 1
    fi
    
    # Default branch to main if not specified
    if [ -z "${branch}" ]; then
        branch="main"
    fi
    
    # Check if git is available
    if ! command -v git > /dev/null 2>&1; then
        echo "       ERROR: git is not available for cloning marketplaces" >&2
        return 1
    fi
    
    # Remove target directory if it exists
    if [ -d "${target_dir}" ]; then
        rm -rf "${target_dir}"
    fi
    
    # Create parent directory
    mkdir -p "$(dirname "${target_dir}")"
    
    # Clone the repository
    echo "       Cloning ${source} (branch: ${branch})..."
    if git clone --depth 1 --branch "${branch}" "${source}" "${target_dir}" 2>/dev/null; then
        echo "       Successfully cloned marketplace"
        return 0
    else
        # Try without branch specification (for default branch)
        echo "       Retrying clone with default branch..."
        if git clone --depth 1 "${source}" "${target_dir}" 2>/dev/null; then
            echo "       Successfully cloned marketplace (default branch)"
            return 0
        fi
    fi
    
    echo "       ERROR: Failed to clone marketplace from ${source}" >&2
    return 1
}

# Validate marketplace structure
# Checks for expected plugin manifest files
# Usage: validate_marketplace marketplace_dir
# Returns: 0 if valid, 1 if invalid
validate_marketplace() {
    local marketplace_dir=$1
    
    if [ ! -d "${marketplace_dir}" ]; then
        echo "       ERROR: Marketplace directory does not exist: ${marketplace_dir}" >&2
        return 1
    fi
    
    # Look for plugins directory or plugin manifests
    local plugin_count=0
    
    # Check for plugins/ subdirectory (common structure)
    if [ -d "${marketplace_dir}/plugins" ]; then
        for plugin_dir in "${marketplace_dir}/plugins"/*; do
            if [ -d "${plugin_dir}" ]; then
                # Check for plugin.json or plugin.yml
                if [ -f "${plugin_dir}/plugin.json" ] || [ -f "${plugin_dir}/plugin.yml" ] || [ -f "${plugin_dir}/plugin.yaml" ]; then
                    plugin_count=$((plugin_count + 1))
                fi
            fi
        done
    fi
    
    # Also check root level for plugin directories
    for plugin_dir in "${marketplace_dir}"/*; do
        if [ -d "${plugin_dir}" ] && [ "$(basename "${plugin_dir}")" != "plugins" ]; then
            if [ -f "${plugin_dir}/plugin.json" ] || [ -f "${plugin_dir}/plugin.yml" ] || [ -f "${plugin_dir}/plugin.yaml" ]; then
                plugin_count=$((plugin_count + 1))
            fi
        fi
    done
    
    if [ ${plugin_count} -eq 0 ]; then
        echo "       WARNING: No valid plugins found in marketplace" >&2
        # Don't fail - marketplace might have different structure
        return 0
    fi
    
    echo "       Found ${plugin_count} plugin(s) in marketplace"
    return 0
}

# Find a plugin directory within a marketplace
# Usage: find_plugin_in_marketplace marketplace_dir plugin_name
# Outputs: path to plugin directory (or empty if not found)
find_plugin_in_marketplace() {
    local marketplace_dir=$1
    local plugin_name=$2
    
    # Check plugins/ subdirectory first
    if [ -d "${marketplace_dir}/plugins/${plugin_name}" ]; then
        echo "${marketplace_dir}/plugins/${plugin_name}"
        return 0
    fi
    
    # Check root level
    if [ -d "${marketplace_dir}/${plugin_name}" ]; then
        echo "${marketplace_dir}/${plugin_name}"
        return 0
    fi
    
    # Not found
    return 1
}

# Install a plugin from a marketplace to the application
# Usage: install_plugin plugin_source_dir target_plugins_dir plugin_name
# Returns: 0 on success, 1 on failure
install_plugin() {
    local plugin_source_dir=$1
    local target_plugins_dir=$2
    local plugin_name=$3
    
    if [ ! -d "${plugin_source_dir}" ]; then
        echo "       ERROR: Plugin source directory not found: ${plugin_source_dir}" >&2
        return 1
    fi
    
    # Create target directory
    local target_plugin_dir="${target_plugins_dir}/${plugin_name}"
    mkdir -p "${target_plugin_dir}"
    
    # Copy plugin files
    if cp -r "${plugin_source_dir}"/* "${target_plugin_dir}/" 2>/dev/null; then
        echo "       Installed plugin: ${plugin_name}" >&2
        return 0
    else
        echo "       ERROR: Failed to install plugin: ${plugin_name}" >&2
        return 1
    fi
}

# Install all specified plugins from a marketplace
# Usage: install_marketplace_plugins marketplace_dir plugins_json target_plugins_dir
# plugins_json is a JSON array of plugin names
# Returns: number of successfully installed plugins
install_marketplace_plugins() {
    local marketplace_dir=$1
    local plugins_json=$2
    local target_plugins_dir=$3
    
    if [ ! -d "${marketplace_dir}" ]; then
        echo "       ERROR: Marketplace directory not found" >&2
        return 0
    fi
    
    # Create target plugins directory
    mkdir -p "${target_plugins_dir}"
    
    local installed_count=0
    
    # Parse plugin names from JSON array using Python
    if command -v python3 > /dev/null 2>&1; then
        local plugin_names=$(python3 -c "import json; plugins=${plugins_json}; print('\n'.join(plugins))" 2>/dev/null)
        
        while IFS= read -r plugin_name; do
            if [ -n "${plugin_name}" ]; then
                # Find plugin in marketplace
                local plugin_source=$(find_plugin_in_marketplace "${marketplace_dir}" "${plugin_name}")
                
                if [ -n "${plugin_source}" ] && [ -d "${plugin_source}" ]; then
                    if install_plugin "${plugin_source}" "${target_plugins_dir}" "${plugin_name}"; then
                        installed_count=$((installed_count + 1))
                    fi
                else
                    echo "       WARNING: Plugin not found in marketplace: ${plugin_name}" >&2
                fi
            fi
        done <<< "${plugin_names}"
    else
        echo "       WARNING: Python3 not available for parsing plugin list" >&2
    fi
    
    echo "${installed_count}"
}

# Extract skills from a plugin to the skills directory
# This is a workaround for GitHub issue #10113 where Claude Code
# incorrectly resolves skill paths for git-installed marketplace plugins
# Usage: extract_plugin_skills plugin_dir target_skills_dir plugin_name
# Returns: number of skills extracted
extract_plugin_skills() {
    local plugin_dir=$1
    local target_skills_dir=$2
    local plugin_name=$3
    
    if [ ! -d "${plugin_dir}" ]; then
        return 0
    fi
    
    local extracted_count=0
    
    # Check for skills/ directory within the plugin
    local plugin_skills_dir="${plugin_dir}/skills"
    if [ ! -d "${plugin_skills_dir}" ]; then
        # Also check for skill/ (singular)
        plugin_skills_dir="${plugin_dir}/skill"
    fi
    
    if [ ! -d "${plugin_skills_dir}" ]; then
        # No skills directory in this plugin
        return 0
    fi
    
    # Create target skills directory
    mkdir -p "${target_skills_dir}"
    
    # Copy each skill directory
    for skill_dir in "${plugin_skills_dir}"/*; do
        if [ -d "${skill_dir}" ]; then
            local skill_name=$(basename "${skill_dir}")
            local target_skill_dir="${target_skills_dir}/${skill_name}"
            
            # Avoid overwriting existing skills
            if [ -d "${target_skill_dir}" ]; then
                echo "       WARNING: Skill already exists, skipping: ${skill_name}" >&2
                continue
            fi
            
            # Copy skill directory
            if cp -r "${skill_dir}" "${target_skill_dir}" 2>/dev/null; then
                # Validate the skill has SKILL.md
                if [ -f "${target_skill_dir}/SKILL.md" ]; then
                    echo "       Extracted skill from plugin ${plugin_name}: ${skill_name}" >&2
                    extracted_count=$((extracted_count + 1))
                else
                    echo "       WARNING: Skill missing SKILL.md, removing: ${skill_name}" >&2
                    rm -rf "${target_skill_dir}"
                fi
            fi
        fi
    done
    
    echo "${extracted_count}"
}

# Extract skills from all installed plugins
# Usage: extract_all_plugin_skills plugins_dir skills_dir
# Returns: total number of skills extracted
extract_all_plugin_skills() {
    local plugins_dir=$1
    local skills_dir=$2
    
    if [ ! -d "${plugins_dir}" ]; then
        echo "0"
        return 0
    fi
    
    local total_extracted=0
    
    for plugin_dir in "${plugins_dir}"/*; do
        if [ -d "${plugin_dir}" ]; then
            local plugin_name=$(basename "${plugin_dir}")
            local extracted=$(extract_plugin_skills "${plugin_dir}" "${skills_dir}" "${plugin_name}")
            total_extracted=$((total_extracted + extracted))
        fi
    done
    
    echo "${total_extracted}"
}

# Main plugin marketplace configuration function
# Parses config, clones marketplaces, installs plugins, and extracts skills
# Usage: configure_plugin_marketplaces build_dir deps_dir index
configure_plugin_marketplaces() {
    local build_dir=$1
    local deps_dir=$2
    local index=$3
    
    echo "-----> Configuring Plugin Marketplaces"
    
    # Check for config file
    local config_file="${build_dir}/.claude-code-config.yml"
    if [ ! -f "${config_file}" ]; then
        echo "       No configuration file found, skipping marketplace configuration"
        return 0
    fi
    
    # Parse plugin marketplaces from config
    local marketplaces_json_file="${build_dir}/.claude-marketplaces-temp.json"
    if ! parse_plugin_marketplaces "${config_file}" "${marketplaces_json_file}"; then
        echo "       No plugin marketplaces configured"
        rm -f "${marketplaces_json_file}"
        return 0
    fi
    
    # Check if we have any marketplaces
    local marketplace_count=$(python3 -c "import json; data=json.load(open('${marketplaces_json_file}')); print(len(data))" 2>/dev/null || echo "0")
    if [ "${marketplace_count}" -eq 0 ]; then
        echo "       No plugin marketplaces configured"
        rm -f "${marketplaces_json_file}"
        return 0
    fi
    
    echo "       Found ${marketplace_count} plugin marketplace(s) to configure"
    
    # Set up directories
    local marketplaces_cache_dir="${deps_dir}/${index}/plugins/marketplaces"
    local app_plugins_dir="${build_dir}/.claude/plugins"
    local app_skills_dir="${build_dir}/.claude/skills"
    
    mkdir -p "${marketplaces_cache_dir}"
    mkdir -p "${app_plugins_dir}"
    mkdir -p "${app_skills_dir}"
    
    local total_plugins_installed=0
    local total_skills_extracted=0
    
    # Process each marketplace using a temp file to avoid subshell variable scope issues
    local marketplace_list_file="${build_dir}/.claude-marketplace-list-temp.txt"
    python3 -c "
import json
import sys

with open('${marketplaces_json_file}') as f:
    marketplaces = json.load(f)

for m in marketplaces:
    # Output format: name|source|branch|plugin1,plugin2,...
    plugins = ','.join(m.get('plugins', []))
    print(f\"{m.get('name', '')}|{m.get('source', '')}|{m.get('branch', 'main')}|{plugins}\")
" 2>/dev/null > "${marketplace_list_file}"

    # Read from file instead of pipe to avoid subshell
    while IFS='|' read -r name source branch plugins; do
        if [ -z "${name}" ] || [ -z "${source}" ]; then
            echo "       WARNING: Skipping invalid marketplace entry (missing name or source)"
            continue
        fi
        
        echo "       Processing marketplace: ${name}"
        
        # Clone the marketplace
        local marketplace_dir="${marketplaces_cache_dir}/${name}"
        if ! clone_marketplace "${source}" "${branch}" "${marketplace_dir}"; then
            echo "       WARNING: Failed to clone marketplace: ${name}"
            continue
        fi
        
        # Install plugins
        if [ -n "${plugins}" ]; then
            # Convert comma-separated list to JSON array
            local plugins_json=$(python3 -c "import json; print(json.dumps('${plugins}'.split(',')))" 2>/dev/null)
            local installed=$(install_marketplace_plugins "${marketplace_dir}" "${plugins_json}" "${app_plugins_dir}")
            total_plugins_installed=$((total_plugins_installed + installed))
        fi
    done < "${marketplace_list_file}"
    
    # Clean up temp file
    rm -f "${marketplace_list_file}"
    
    # Extract skills from all installed plugins (workaround for #10113)
    if [ -d "${app_plugins_dir}" ]; then
        echo "       Extracting skills from installed plugins..."
        local skills_extracted=$(extract_all_plugin_skills "${app_plugins_dir}" "${app_skills_dir}")
        total_skills_extracted=$((total_skills_extracted + skills_extracted))
    fi
    
    # Clean up temp file
    rm -f "${marketplaces_json_file}"
    
    echo "       Plugin marketplace configuration complete"
    echo "       Total plugins installed: ${total_plugins_installed}"
    echo "       Total skills extracted: ${total_skills_extracted}"
    
    return 0
}
