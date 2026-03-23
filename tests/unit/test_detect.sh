#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DETECT_SCRIPT="${BP_DIR}/bin/detect"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_test_header() {
    echo -e "\n${YELLOW}Running: $1${NC}"
}

assert_exit_code() {
    local expected=$1
    local actual=$2
    local test_name=$3
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "${expected}" -eq "${actual}" ]; then
        echo -e "${GREEN}✓ PASS${NC}: ${test_name}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: ${test_name}"
        echo "  Expected exit code: ${expected}, Got: ${actual}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

TEST_DIR=$(mktemp -d)
PLATFORM_DIR=$(mktemp -d)
BUILD_PLAN=$(mktemp)
trap "rm -rf ${TEST_DIR} ${PLATFORM_DIR} ${BUILD_PLAN}" EXIT

mkdir -p "${PLATFORM_DIR}/env"

run_detect() {
    local exit_code=0
    export CNB_PLATFORM_DIR="${PLATFORM_DIR}"
    export CNB_BUILD_PLAN_PATH="${BUILD_PLAN}"
    (cd "$TEST_DIR" && "${DETECT_SCRIPT}") > /dev/null 2>&1 || exit_code=$?
    echo "" > "${BUILD_PLAN}"
    echo "${exit_code}"
}

print_test_header "Test 1: Detection with .claude-code-config.yml file"
touch "${TEST_DIR}/.claude-code-config.yml"
EXIT_CODE=$(run_detect)
assert_exit_code 0 ${EXIT_CODE} "Should detect when .claude-code-config.yml exists"
rm -f "${TEST_DIR}/.claude-code-config.yml"

print_test_header "Test 2: Detection with CLAUDE_CODE_ENABLED platform env"
echo -n "true" > "${PLATFORM_DIR}/env/CLAUDE_CODE_ENABLED"
EXIT_CODE=$(run_detect)
assert_exit_code 0 ${EXIT_CODE} "Should detect when CLAUDE_CODE_ENABLED=true"
rm -f "${PLATFORM_DIR}/env/CLAUDE_CODE_ENABLED"

print_test_header "Test 3: Detection with .claude/ state directory"
mkdir -p "${TEST_DIR}/.claude"
EXIT_CODE=$(run_detect)
assert_exit_code 0 ${EXIT_CODE} "Should detect when .claude/ directory exists"
rm -rf "${TEST_DIR}/.claude"

print_test_header "Test 4: No detection when none of the conditions are met"
EXIT_CODE=$(run_detect)
assert_exit_code 100 ${EXIT_CODE} "Should exit 100 when no conditions are met"

print_test_header "Test 5: CLAUDE_CODE_ENABLED=false should NOT trigger detection"
echo -n "false" > "${PLATFORM_DIR}/env/CLAUDE_CODE_ENABLED"
EXIT_CODE=$(run_detect)
assert_exit_code 100 ${EXIT_CODE} "Should exit 100 when CLAUDE_CODE_ENABLED=false"
rm -f "${PLATFORM_DIR}/env/CLAUDE_CODE_ENABLED"

print_test_header "Test 6: Build plan output contains provides/requires"
touch "${TEST_DIR}/.claude-code-config.yml"
export CNB_PLATFORM_DIR="${PLATFORM_DIR}"
export CNB_BUILD_PLAN_PATH="${BUILD_PLAN}"
(cd "$TEST_DIR" && "${DETECT_SCRIPT}") > /dev/null 2>&1 || true
if grep -q '[[provides]]' "${BUILD_PLAN}" && grep -q '[[requires]]' "${BUILD_PLAN}"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}: Build plan contains provides and requires"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: Build plan should contain provides and requires"
fi
rm -f "${TEST_DIR}/.claude-code-config.yml"
echo "" > "${BUILD_PLAN}"

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
