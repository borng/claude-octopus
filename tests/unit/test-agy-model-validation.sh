#!/usr/bin/env bash
# Test: validate_agy_model_name against tab-separated `agy models` output
#
# Regression: the agy CLI emits "name<TAB>Description" lines (e.g.
# "gemini-3.1-pro-high\tGemini 3.1 Pro (High)"), but validation used to
# compare OCTOPUS_AGY_MODEL against each WHOLE line, so every concrete
# model name failed and phases aborted with
# "ERROR: Invalid model name in OCTOPUS_AGY_MODEL".

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Testing validate_agy_model_name (tab-separated agy models output)"
echo "================================================================="

# Mock log function
log() { :; }
export -f log
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

source "${PLUGIN_DIR}/scripts/lib/model-resolver.sh"

# Fake agy CLI emitting the current tab-separated format (plus a CRLF line
# to cover Windows-tainted output).
MOCK_BIN="$(mktemp -d /tmp/octo-agy-mock.XXXXXX)"
trap 'rm -rf "$MOCK_BIN"' EXIT
cat > "$MOCK_BIN/agy" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "models" ]]; then
    printf 'gemini-3.1-pro-high\tGemini 3.1 Pro (High)\n'
    printf 'gemini-3.7-flash-medium\tGemini 3.7 Flash (Medium)\n'
    printf 'gemini-3.6-flash-low\tGemini 3.6 Flash (Low)\r\n'
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/agy"
export PATH="$MOCK_BIN:$PATH"

TESTS_RUN=0
TESTS_PASSED=0

assert_rc() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local expected_rc="$1"
    local desc="$2"
    shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq "$expected_rc" ]]; then
        echo -e "${GREEN}✓${NC} $desc (rc=$rc)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $desc (expected rc=$expected_rc, got rc=$rc)"
        exit 1
    fi
}

# Fast path stays intact
assert_rc 0 "'default' passes without consulting agy" \
    validate_agy_model_name "default"
assert_rc 0 "'agy/default' passes without consulting agy" \
    validate_agy_model_name "agy/default"

# Regression: concrete model names from tab-separated output must validate
assert_rc 0 "concrete model name validates against tab-separated output" \
    validate_agy_model_name "gemini-3.1-pro-high"
assert_rc 0 "second listed model validates" \
    validate_agy_model_name "gemini-3.7-flash-medium"
assert_rc 0 "CRLF-terminated line still validates" \
    validate_agy_model_name "gemini-3.6-flash-low"

# Unknown names must still be rejected
assert_rc 1 "unknown model name is rejected" \
    validate_agy_model_name "gemini-9.9-nonexistent"
assert_rc 1 "description text alone is not a model name" \
    validate_agy_model_name "Gemini 3.1 Pro (High)"
assert_rc 1 "empty model name is rejected" \
    validate_agy_model_name ""

echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
[[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]]
