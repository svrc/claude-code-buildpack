#!/usr/bin/env bash
# tests/unit/test_validator.sh: Unit tests for lib/validator.sh

set -e

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR_LIB="${BP_DIR}/lib/validator.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source the validator library
source "${VALIDATOR_LIB}"

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

# Test 1: Validate required tools
print_test_header "Test 1: Validate required tools exist"
if validate_required_tools > /dev/null 2>&1; then
    assert_success "All required tools should be available"
else
    assert_failure "All required tools should be available"
fi

# Test 2: Command exists check
print_test_header "Test 2: Command exists check"
if command_exists "bash"; then
    assert_success "Should detect bash command exists"
else
    assert_failure "Should detect bash command exists"
fi

if command_exists "nonexistent_command_xyz"; then
    assert_failure "Should not detect nonexistent command"
else
    assert_success "Should not detect nonexistent command"
fi

# Test 3: Validate Node.js version format
print_test_header "Test 3: Validate Node.js version format"

if validate_nodejs_version "20.11.0" > /dev/null 2>&1; then
    assert_success "Valid version format (20.11.0) should pass"
else
    assert_failure "Valid version format (20.11.0) should pass"
fi

if validate_nodejs_version "invalid" > /dev/null 2>&1; then
    assert_failure "Invalid version format should fail"
else
    assert_success "Invalid version format should fail"
fi

# Test 4: Validate installation directory
print_test_header "Test 4: Validate installation directory"

if validate_install_dir "${TEST_DIR}" > /dev/null 2>&1; then
    assert_success "Valid writable directory should pass"
else
    assert_failure "Valid writable directory should pass"
fi

if validate_install_dir "/nonexistent/directory" > /dev/null 2>&1; then
    assert_failure "Nonexistent directory should fail"
else
    assert_success "Nonexistent directory should fail"
fi

# Test 5: API key format validation
print_test_header "Test 5: API key format validation"

export CNB_PLATFORM_DIR="${TEST_DIR}/platform"
mkdir -p "${CNB_PLATFORM_DIR}/env"

export ANTHROPIC_API_KEY="sk-ant-test123"
if validate_environment 2>&1 | grep -q "API key format validated"; then
    assert_success "Valid API key format should be recognized"
else
    assert_failure "Valid API key format should be recognized"
fi

export ANTHROPIC_API_KEY="invalid-key"
if validate_environment 2>&1 | grep -q "appears invalid"; then
    assert_success "Invalid API key format should be detected"
else
    assert_failure "Invalid API key format should be detected"
fi

unset ANTHROPIC_API_KEY

# Test 6: OAuth token validation
print_test_header "Test 6: OAuth token validation"

export CLAUDE_CODE_OAUTH_TOKEN="test-oauth-token-123"
if validate_environment 2>&1 | grep -q "OAuth token detected"; then
    assert_success "Valid OAuth token should be recognized"
else
    assert_failure "Valid OAuth token should be recognized"
fi

unset CLAUDE_CODE_OAUTH_TOKEN

export ANTHROPIC_API_KEY="sk-ant-test456"
export CLAUDE_CODE_OAUTH_TOKEN="test-oauth-token-456"
if validate_environment 2>&1 | grep -q "API key format validated"; then
    assert_success "Should accept when both credentials are present"
else
    assert_failure "Should accept when both credentials are present"
fi

unset ANTHROPIC_API_KEY
unset CLAUDE_CODE_OAUTH_TOKEN

if validate_environment 2>&1 | grep -q "Neither.*is set"; then
    assert_success "Should warn when neither credential is set"
else
    assert_failure "Should warn when neither credential is set"
fi

# Test 7: Config file validation
print_test_header "Test 7: Config file validation"

# Create a test config file
TEST_CONFIG="${TEST_DIR}/test-config.yml"
touch "${TEST_CONFIG}"

if validate_config_file "${TEST_CONFIG}" > /dev/null 2>&1; then
    assert_success "Existing config file should validate"
else
    assert_failure "Existing config file should validate"
fi

if validate_config_file "/nonexistent/config.yml" > /dev/null 2>&1; then
    assert_failure "Nonexistent config file should fail"
else
    assert_success "Nonexistent config file should fail"
fi

# Print summary
echo -e "\n${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}Test Summary${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo -e "Tests Run:    ${TESTS_RUN}"
echo -e "${GREEN}Tests Passed: ${TESTS_PASSED}${NC}"

if [ ${TESTS_FAILED} -gt 0 ]; then
    echo -e "${RED}Tests Failed: ${TESTS_FAILED}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
