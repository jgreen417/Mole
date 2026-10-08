#!/usr/bin/env bats

load helpers/common

setup_file() {
	mole_test_setup_project_root

	TEST_HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-optimize-unavailable.XXXXXX")"
	export TEST_HOME
}

teardown_file() {
	if [[ "$TEST_HOME" == "${BATS_TEST_DIRNAME}/tmp-optimize-unavailable."* ]]; then
		rm -rf "$TEST_HOME"
	fi
}

# A directory the caller cannot read (chmod 000, or a privacy-protected path
# without Full Disk Access) is out of reach, not a failed scan. GNU/BSD find
# exits 1 with a permission error; that must not publish a task failure.
@test "shared file list scan reports unavailable when the directory is unreadable" {
	# run_with_timeout execs a binary, so the mock must be a PATH command,
	# not a shell function the child bash would never see.
	# shellcheck disable=SC2016  # $1 expands when the generated stub runs, not here.
	mole_test_fake_command find 'printf "find: %s: Operation not permitted\n" "$1" >&2; exit 1'

	run env HOME="$TEST_HOME/shared-list-unreadable" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"

mkdir -p "$HOME/Library/Application Support/com.apple.sharedfilelist"

execute_optimization shared_file_list_repair
[[ "$(optimize_outcome_count failed)" == "0" ]] || exit 1
[[ "$(optimize_outcome_count unavailable)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Shared file lists not readable"* ]] || return 1
	[[ "$output" != *"Failed to scan shared file lists"* ]] || return 1
}

# A time ceiling is a capability limit, not a failed operation: the audit
# published no conclusions, so it must not badge the run as failed.
@test "login items audit reports unavailable when a probe times out" {
	run env HOME="$TEST_HOME/login-probe-timeout" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"

# The scripted test run sets this to skip the audit entirely; this test is
# exercising the audit, so it must not leak in.
unset MOLE_TEST_NO_AUTH

_login_items_snapshot() { printf 'Stale Entry\tmissing value\n'; }
_login_item_build_app_inventory() { : > "$1"; return 0; }
_login_item_app_exists() { return 124; }

execute_optimization login_items_audit
[[ "$(optimize_outcome_count failed)" == "0" ]] || exit 1
[[ "$(optimize_outcome_count unavailable)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"time limit reached"* ]] || return 1
}

@test "login items audit reports unavailable when the snapshot times out" {
	run env HOME="$TEST_HOME/login-snapshot-timeout" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TIMEOUT_HINT_SCAN_SEC=0 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"

unset MOLE_TEST_NO_AUTH

# A zero audit budget expires the deadline before the snapshot can run.
execute_optimization login_items_audit
[[ "$(optimize_outcome_count failed)" == "0" ]] || exit 1
[[ "$(optimize_outcome_count unavailable)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"snapshot timed out"* ]] || return 1
}
