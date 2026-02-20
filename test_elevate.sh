#!/bin/bash
# test_elevate.sh — Test harness for the elevate CLI
# Self-contained, zero external dependencies.

set -euo pipefail

# ── Test Framework ────────────────────────────────────────────────────────────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

_test_begin() { CURRENT_TEST="$1"; TESTS_RUN=$((TESTS_RUN + 1)); }

_test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '  \033[32m✓\033[0m %s\n' "$CURRENT_TEST"
}

_test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  \033[31m✗\033[0m %s — %s\n' "$CURRENT_TEST" "$1"
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then _test_pass
    else _test_fail "${msg:+$msg: }expected '$expected', got '$actual'"; fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then _test_pass
    else _test_fail "${msg:+$msg: }'$haystack' does not contain '$needle'"; fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then _test_pass
    else _test_fail "${msg:+$msg: }should not contain '$needle'"; fi
}

assert_exit() {
    local expected_code="$1"; shift
    local actual_code=0
    ( "$@" ) >/dev/null 2>&1 || actual_code=$?
    if [[ "$actual_code" -eq "$expected_code" ]]; then _test_pass
    else _test_fail "expected exit $expected_code, got $actual_code"; fi
}

# ── Source Script Under Test ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ELEVATE_TESTING=1
# shellcheck source=./elevate
source "$SCRIPT_DIR/elevate"

# ── Mock Setup ────────────────────────────────────────────────────────────────
MOCK_ADMIN=false
MOCK_APP_INSTALLED=true
MOCK_APP_RUNNING=true
MOCK_ACCESSIBILITY=true
MOCK_MENU_STATUS="Elevate24 Locked"
MOCK_SESSION_TIME=600
MOCK_AS_RESULT="OK"
MOCK_POPOVER_TEXTS=""

_reset_mocks() {
    MOCK_ADMIN=false
    MOCK_APP_INSTALLED=true
    MOCK_APP_RUNNING=true
    MOCK_ACCESSIBILITY=true
    MOCK_MENU_STATUS="Elevate24 Locked"
    MOCK_SESSION_TIME=600
    MOCK_AS_RESULT="OK"
    MOCK_POPOVER_TEXTS=""
    COMMAND=""
    OPT_QUIET=false
    OPT_NO_COLOR=true
    OPT_TIMEOUT=30
    OPT_REASON="Run scripts"
    _setup_colors
}

# Override low-level wrappers
_dseditgroup() {
    if [[ "$MOCK_ADMIN" == true ]]; then
        echo "yes $(whoami) is a member of admin"; return 0
    else
        echo "no $(whoami) is NOT a member of admin"; return 1
    fi
}

_pgrep() { [[ "$MOCK_APP_RUNNING" == true ]]; }

_osascript() {
    [[ "$MOCK_ACCESSIBILITY" != true ]] && return 1
    local script="$*"
    case "$script" in
        *"get name of process"*) echo "$APP_NAME" ;;
        *"accessibility description"*) echo "$MOCK_MENU_STATUS" ;;
        *) echo "$MOCK_AS_RESULT" ;;
    esac
}

_defaults_read() { echo "$MOCK_SESSION_TIME"; }
_pbpaste() { echo ""; }
_check_app_installed() { [[ "$MOCK_APP_INSTALLED" == true ]]; }

# Override high-level AppleScript functions
_as_start_session()      { echo "$MOCK_AS_RESULT"; }
_as_extend_session()     { echo "$MOCK_AS_RESULT"; }
_as_end_session()        { echo "$MOCK_AS_RESULT"; }
_as_read_popover_texts() { echo "$MOCK_POPOVER_TEXTS"; }
_as_close_popover()      { true; }

# ── Test: Argument Parsing ────────────────────────────────────────────────────
test_parse_args() {
    printf '\n\033[1mArgument Parsing\033[0m\n'

    _test_begin "parse 'status' command"
    _reset_mocks; parse_args status
    assert_eq "status" "$COMMAND"

    _test_begin "parse 'start' command"
    _reset_mocks; parse_args start
    assert_eq "start" "$COMMAND"

    _test_begin "parse 'extend' command"
    _reset_mocks; parse_args extend
    assert_eq "extend" "$COMMAND"

    _test_begin "parse 'end' command"
    _reset_mocks; parse_args end
    assert_eq "end" "$COMMAND"

    _test_begin "parse 'help' command"
    _reset_mocks; parse_args help
    assert_eq "help" "$COMMAND"

    _test_begin "parse --help flag"
    _reset_mocks; parse_args --help
    assert_eq "help" "$COMMAND"

    _test_begin "parse --reason flag"
    _reset_mocks; parse_args start --reason "System diagnostics"
    assert_eq "System diagnostics" "$OPT_REASON"

    _test_begin "parse --quiet flag"
    _reset_mocks; parse_args --quiet status
    assert_eq "true" "$OPT_QUIET"

    _test_begin "parse -q shorthand"
    _reset_mocks; parse_args -q status
    assert_eq "true" "$OPT_QUIET"

    _test_begin "parse --no-color flag"
    _reset_mocks; OPT_NO_COLOR=false; parse_args --no-color status
    assert_eq "true" "$OPT_NO_COLOR"

    _test_begin "parse --timeout flag"
    _reset_mocks; parse_args start --timeout 45
    assert_eq "45" "$OPT_TIMEOUT"

    _test_begin "options before command"
    _reset_mocks; parse_args --quiet --no-color status
    assert_eq "status" "$COMMAND"

    _test_begin "reject no command"
    _reset_mocks; assert_exit 2 parse_args

    _test_begin "reject unknown command"
    _reset_mocks; assert_exit 2 parse_args foobar

    _test_begin "reject unknown option"
    _reset_mocks; assert_exit 2 parse_args --bogus

    _test_begin "reject --timeout without value"
    _reset_mocks; assert_exit 2 parse_args start --timeout

    _test_begin "reject non-numeric --timeout"
    _reset_mocks; assert_exit 2 parse_args start --timeout abc

    _test_begin "reject multiple commands"
    _reset_mocks; assert_exit 2 parse_args status start

    _test_begin "--version prints version"
    _reset_mocks
    local out
    out=$(parse_args --version 2>&1) || true
    assert_contains "$out" "elevate"
}

# ── Test: Status Detection ────────────────────────────────────────────────────
test_status_detection() {
    printf '\n\033[1mStatus Detection\033[0m\n'

    _test_begin "_is_admin true when admin"
    _reset_mocks; MOCK_ADMIN=true
    if _is_admin; then _test_pass; else _test_fail "should be admin"; fi

    _test_begin "_is_admin false when not admin"
    _reset_mocks; MOCK_ADMIN=false
    if _is_admin; then _test_fail "should not be admin"; else _test_pass; fi

    _test_begin "_get_menu_bar_status returns Locked"
    _reset_mocks; MOCK_MENU_STATUS="Elevate24 Locked"
    assert_eq "Elevate24 Locked" "$(_get_menu_bar_status)"

    _test_begin "_get_menu_bar_status returns Unlocked"
    _reset_mocks; MOCK_MENU_STATUS="Elevate24 Unlocked"
    assert_eq "Elevate24 Unlocked" "$(_get_menu_bar_status)"

    _test_begin "_get_session_time returns configured value"
    _reset_mocks; MOCK_SESSION_TIME=600
    assert_eq "600" "$(_get_session_time)"

    _test_begin "_get_session_time returns custom value"
    _reset_mocks; MOCK_SESSION_TIME=1200
    assert_eq "1200" "$(_get_session_time)"
}

# ── Test: Preflight Checks ───────────────────────────────────────────────────
test_preflight() {
    printf '\n\033[1mPreflight Checks\033[0m\n'

    _test_begin "preflight passes when all OK"
    _reset_mocks; assert_exit 0 _preflight

    _test_begin "preflight fails: app not installed"
    _reset_mocks; MOCK_APP_INSTALLED=false
    assert_exit 1 _preflight

    _test_begin "preflight fails: app not running"
    _reset_mocks; MOCK_APP_RUNNING=false
    assert_exit 1 _preflight

    _test_begin "preflight fails: no accessibility"
    _reset_mocks; MOCK_ACCESSIBILITY=false
    assert_exit 1 _preflight

    _test_begin "preflight error message: not installed"
    _reset_mocks; MOCK_APP_INSTALLED=false
    local out
    out=$( (_preflight) 2>&1) || true
    assert_contains "$out" "not installed"

    _test_begin "preflight error message: not running"
    _reset_mocks; MOCK_APP_RUNNING=false
    local out
    out=$( (_preflight) 2>&1) || true
    assert_contains "$out" "not running"

    _test_begin "preflight error message: accessibility"
    _reset_mocks; MOCK_ACCESSIBILITY=false
    local out
    out=$( (_preflight) 2>&1) || true
    assert_contains "$out" "Accessibility"
}

# ── Test: Commands ────────────────────────────────────────────────────────────
test_commands() {
    printf '\n\033[1mCommand Execution\033[0m\n'

    _test_begin "cmd_status: NOT ELEVATED when not admin"
    _reset_mocks; MOCK_ADMIN=false
    local out; out=$(cmd_status 2>&1)
    assert_contains "$out" "NOT ELEVATED"

    _test_begin "cmd_status: ELEVATED when admin"
    _reset_mocks; MOCK_ADMIN=true; MOCK_MENU_STATUS="Elevate24 Unlocked"
    local out; out=$(cmd_status 2>&1)
    assert_contains "$out" "ELEVATED"

    _test_begin "cmd_status: shows session duration"
    _reset_mocks; MOCK_ADMIN=false; MOCK_SESSION_TIME=600
    local out; out=$(cmd_status 2>&1)
    assert_contains "$out" "10 minutes"

    _test_begin "cmd_status: shows menu bar status"
    _reset_mocks; MOCK_ADMIN=false; MOCK_MENU_STATUS="Elevate24 Locked"
    local out; out=$(cmd_status 2>&1)
    assert_contains "$out" "Elevate24 Locked"

    _test_begin "cmd_start: warns when already admin"
    _reset_mocks; MOCK_ADMIN=true
    local out; out=$(cmd_start 2>&1)
    assert_contains "$out" "Already elevated"

    _test_begin "cmd_start: fails on AppleScript error"
    _reset_mocks; MOCK_ADMIN=false; MOCK_AS_RESULT="ERROR:Popover did not open"
    assert_exit 1 cmd_start

    _test_begin "cmd_start: shows error message"
    _reset_mocks; MOCK_ADMIN=false; MOCK_AS_RESULT="ERROR:Popover did not open"
    local out; out=$( (cmd_start) 2>&1) || true
    assert_contains "$out" "Popover did not open"

    _test_begin "cmd_start: reason not found error"
    _reset_mocks; MOCK_ADMIN=false; MOCK_AS_RESULT="ERROR:Reason not found: Bad Reason"
    OPT_REASON="Bad Reason"
    assert_exit 1 cmd_start

    _test_begin "cmd_extend: fails when not admin"
    _reset_mocks; MOCK_ADMIN=false
    assert_exit 1 cmd_extend

    _test_begin "cmd_extend: error message when not admin"
    _reset_mocks; MOCK_ADMIN=false
    local out; out=$( (cmd_extend) 2>&1) || true
    assert_contains "$out" "Not currently elevated"

    _test_begin "cmd_extend: succeeds when admin"
    _reset_mocks; MOCK_ADMIN=true; MOCK_AS_RESULT="OK"
    local out; out=$(cmd_extend 2>&1)
    assert_contains "$out" "extended"

    _test_begin "cmd_extend: fails on extend blocked"
    _reset_mocks; MOCK_ADMIN=true
    _as_extend_session() { echo "ERROR:Extend button not found. Extension may be blocked by policy."; }
    assert_exit 1 cmd_extend
    _as_extend_session() { echo "$MOCK_AS_RESULT"; }  # restore

    _test_begin "cmd_end: reports nothing when not admin"
    _reset_mocks; MOCK_ADMIN=false
    local out; out=$(cmd_end 2>&1)
    assert_contains "$out" "nothing to end"

    _test_begin "cmd_end: exit 0 when not admin"
    _reset_mocks; MOCK_ADMIN=false
    assert_exit 0 cmd_end

    _test_begin "cmd_end: fails on AppleScript error"
    _reset_mocks; MOCK_ADMIN=true; MOCK_AS_RESULT="ERROR:Revoke button not found"
    assert_exit 1 cmd_end

    _test_begin "cmd_help: shows usage info"
    _reset_mocks
    local out; out=$(cmd_help 2>&1)
    assert_contains "$out" "Usage"

    _test_begin "cmd_help: lists all commands"
    _reset_mocks
    local out; out=$(cmd_help 2>&1)
    assert_contains "$out" "status"
    _test_begin "cmd_help: lists start command"
    assert_contains "$out" "start"
    _test_begin "cmd_help: lists extend command"
    assert_contains "$out" "extend"
    _test_begin "cmd_help: lists end command"
    # 'end' appears in 'extend' too, check for the full line
    assert_contains "$out" "end"
}

# ── Test: Output Formatting ──────────────────────────────────────────────────
test_output() {
    printf '\n\033[1mOutput Formatting\033[0m\n'

    _test_begin "_info suppressed in quiet mode"
    _reset_mocks; OPT_QUIET=true
    assert_eq "" "$(_info "hello")"

    _test_begin "_info prints in normal mode"
    _reset_mocks; OPT_QUIET=false
    assert_eq "hello" "$(_info "hello")"

    _test_begin "_success suppressed in quiet mode"
    _reset_mocks; OPT_QUIET=true
    assert_eq "" "$(_success "done")"

    _test_begin "_warn always prints to stderr"
    _reset_mocks; OPT_QUIET=true
    local out; out=$(_warn "warning" 2>&1)
    assert_contains "$out" "warning"

    _test_begin "_error always prints to stderr"
    _reset_mocks; OPT_QUIET=true
    local out; out=$(_error "oops" 2>&1)
    assert_contains "$out" "oops"
}

# ── Test: Edge Cases ─────────────────────────────────────────────────────────
test_edge_cases() {
    printf '\n\033[1mEdge Cases\033[0m\n'

    _test_begin "status: admin but menu says Locked (stale)"
    _reset_mocks; MOCK_ADMIN=true; MOCK_MENU_STATUS="Elevate24 Locked"
    local out; out=$(cmd_status 2>&1)
    # Should trust dseditgroup (admin=true) over menu bar
    assert_contains "$out" "ELEVATED"

    _test_begin "status: not admin but menu says Unlocked (stale)"
    _reset_mocks; MOCK_ADMIN=false; MOCK_MENU_STATUS="Elevate24 Unlocked"
    local out; out=$(cmd_status 2>&1)
    assert_contains "$out" "NOT ELEVATED"

    _test_begin "start: reason with spaces works"
    _reset_mocks; OPT_REASON="App install / update"
    parse_args start --reason "App install / update"
    assert_eq "App install / update" "$OPT_REASON"

    _test_begin "timeout: custom value used"
    _reset_mocks; parse_args start --timeout 120
    assert_eq "120" "$OPT_TIMEOUT"

    _test_begin "credential capture: username and password parsed"
    _reset_mocks; MOCK_ADMIN=true
    MOCK_POPOVER_TEXTS="TEXT:Local Admin Management
TEXT:Administrator User Name
TEXT:Elevate24Admin
TEXT:Administrator Password
TEXT:xKp2!mNq9Lw
TEXT:2.3.2"
    _as_read_popover_texts() { echo "$MOCK_POPOVER_TEXTS"; }
    local out; out=$(_capture_credentials 2>&1)
    assert_contains "$out" "Elevate24Admin"
    _test_begin "credential capture: password parsed"
    assert_contains "$out" "xKp2!mNq9Lw"
    _as_read_popover_texts() { echo "$MOCK_POPOVER_TEXTS"; }  # restore to use global

    _test_begin "credential capture: empty texts returns failure"
    _reset_mocks
    _as_read_popover_texts() { echo ""; }
    local rc=0
    ( _capture_credentials ) >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc"
    _as_read_popover_texts() { echo "$MOCK_POPOVER_TEXTS"; }
}

# ── Run All Tests ─────────────────────────────────────────────────────────────
printf '\033[1m\nElevate CLI Test Suite\033[0m\n'
printf '%.0s─' {1..40}; printf '\n'

test_parse_args
test_status_detection
test_preflight
test_commands
test_output
test_edge_cases

printf '\n%.0s─' {1..40}; printf '\n'
printf 'Results: %d passed, %d failed, %d total\n' "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_RUN"

if [[ $TESTS_FAILED -gt 0 ]]; then
    printf '\033[31mFAILED\033[0m\n\n'
    exit 1
else
    printf '\033[32mALL PASSED\033[0m\n\n'
    exit 0
fi
