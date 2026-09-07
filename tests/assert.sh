#!/usr/bin/env bash
# The assertions that every tests/*.test.sh file uses. Source this file.
# Do not execute it.
#
# A test file is a plain script. It sources this file, calls assertions, and
# stops. The EXIT trap below prints the tally and sets the exit code, so a test
# file holds no bookkeeping of its own.
#
# `set -e` is OFF on purpose. A failing assertion must report and continue, so
# one run names every problem instead of the first one.

set -uo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"
set +e

PEL_PASS=0
PEL_FAIL=0
PEL_TEMP=()

# tmpdir: make a temporary directory and print it. The report trap below
# removes every one at the end.
#
# A test file must not set its own trap. The EXIT trap below prints the totals.
# A second `trap ... EXIT` replaces that trap. The file then reports nothing,
# and the runner counts no test.
tmpdir() {
	local dir
	dir="$(mktemp -d)"
	PEL_TEMP+=("$dir")
	printf '%s\n' "$dir"
}

# ANCHOR: assertions
# ok NAME: record a test that passed.
ok() {
	PEL_PASS=$((PEL_PASS + 1))
	[ -z "${PEL_TEST_VERBOSE:-}" ] || printf '      ok    %s\n' "$1"
}

# bad NAME REASON: record a test that failed, and say what it wanted.
bad() {
	PEL_FAIL=$((PEL_FAIL + 1))
	printf '  FAIL  %s\n' "$1" >&2
	printf '        %s\n' "$2" >&2
}

# is NAME EXPECTED ACTUAL: the two strings are the same.
is() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		bad "$1" "wanted '$2' and got '$3'"
	fi
}

# has NAME TEXT SUBSTRING: the text holds the substring.
has() {
	case "$2" in
	*"$3"*) ok "$1" ;;
	*) bad "$1" "the output does not hold '$3'. It is: $2" ;;
	esac
}

# hasnt NAME TEXT SUBSTRING: the text does NOT hold the substring. This is the
# assertion that keeps a secret out of a message.
hasnt() {
	case "$2" in
	*"$3"*) bad "$1" "the output holds '$3', and it must not. It is: $2" ;;
	*) ok "$1" ;;
	esac
}

# accepts NAME CMD...: the command returns 0. It runs in a subshell, so a
# command that calls die() stops nothing here.
accepts() {
	local name="$1" status=0
	shift
	("$@") >/dev/null 2>&1 || status=$?
	if [ "$status" -eq 0 ]; then
		ok "$name"
	else
		bad "$name" "the command returned $status, and it had to return 0: $*"
	fi
}

# refuses NAME CMD...: the command returns a failure. Every guard of this
# repository is a refusal, so this is the assertion that tests one.
refuses() {
	local name="$1" status=0
	shift
	("$@") >/dev/null 2>&1 || status=$?
	if [ "$status" -eq 0 ]; then
		bad "$name" "the command returned 0, and it had to refuse: $*"
	else
		ok "$name"
	fi
}

# refuses_with NAME SUBSTRING CMD...: the command refuses AND its message holds
# the substring. Rule: a refusal names the correction, so the message is part of
# the behaviour and not decoration.
refuses_with() {
	local name="$1" want="$2" out status=0
	shift 2
	out="$("$@" 2>&1)" || status=$?
	if [ "$status" -eq 0 ]; then
		bad "$name" "the command returned 0, and it had to refuse: $*"
		return
	fi
	has "$name" "$out" "$want"
}

# mode NAME EXPECTED PATH: the file or the directory has that octal mode.
mode() {
	local got
	got="$(stat -c '%a' "$3" 2>/dev/null)"
	if [ -z "$got" ]; then
		bad "$1" "$3 does not exist, so it has no mode"
		return
	fi
	is "$1" "$2" "$got"
}
# ANCHOR_END: assertions

# The tally. scripts/test.sh reads the counts from PEL_TEST_COUNTS, so the
# runner reports a total and no test file counts anything itself.
#
# The FIRST line reads the exit status of the file. A failure status has
# priority over the totals.
#
# A test file can stop before its last assertion. `set -u` on a variable that is
# not set causes this. A trap that returns its own status of 0 then reports
# "12 passed, 0 failed" for a file that ran one half of its tests. A test suite
# must not report a success for a file that stopped.
pel_test_report() {
	local status=$?
	[ "${#PEL_TEMP[@]}" -eq 0 ] || rm -rf "${PEL_TEMP[@]}"
	[ "$PEL_FAIL" -eq 0 ] || status=1
	[ -z "${PEL_TEST_COUNTS:-}" ] ||
		printf '%s %s\n' "$PEL_PASS" "$PEL_FAIL" >>"$PEL_TEST_COUNTS"
	if [ "$status" -ne 0 ] && [ "$PEL_FAIL" -eq 0 ]; then
		printf '  FAIL  the file stopped early with status %s, after %s test(s)\n' \
			"$status" "$PEL_PASS" >&2
	fi
	printf '    %s passed, %s failed\n' "$PEL_PASS" "$PEL_FAIL"
	exit "$status"
}
trap pel_test_report EXIT
