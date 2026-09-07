#!/usr/bin/env bash
# Run the offline tests of this repository.
#
# The tests reach NOTHING. No libvirt, no Palette tenant, no network, and no
# file outside a temporary directory. So they run on a fresh checkout, they run
# on the hosted CI runner, and they run in a second. `just lint` calls this
# script for that reason.
#
# The tests examine the guards. A guard is a test in a script that refuses a
# condition. Each guard prevents a known failure:
#
#   a cluster name that libvirt accepts and Palette refuses
#   a pod range that contains the cluster subnet
#   a cluster list that counts a deleted cluster
#
# A small change to one `if` statement can stop a guard. The recipe then returns
# 0 and gives no message. Thus each guard needs a test.
#
# What they do NOT test is the tenant and the machines. `just cluster-verify`
# tests a live cluster and the e2e workflow builds one every night. Those need
# a tenant, and this needs none: the two answer different questions.
#
# Each file in tests/ operates as a separate process. Thus a replacement
# function for `api`, or a temporary directory, cannot reach the next file.
#
#   test.sh              every test file
#   test.sh lib          the files whose name holds "lib"
#
# Env: PEL_TEST_VERBOSE=1 names every test that passes, not the failures only.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$(repo_root)"
need python3

filter="${1:-}"

# The tally goes in a file, because each test file is a separate process.
counts="$(mktemp)"
trap 'rm -f "$counts"' EXIT
export PEL_TEST_COUNTS="$counts"

files=()
for file in tests/*.test.sh; do
	[ -e "$file" ] || continue
	[ -z "$filter" ] || case "$file" in *"$filter"*) ;; *) continue ;; esac
	files+=("$file")
done

[ "${#files[@]}" -gt 0 ] || die "no test file matches '$filter'.
     The tests are in tests/*.test.sh. To run all of them:  just test"

failed=()
for file in "${files[@]}"; do
	printf '==> %s\n' "$file"
	bash "$file" || failed+=("$file")
done

pass=0
fail=0
while read -r p f; do
	pass=$((pass + p))
	fail=$((fail + f))
done <"$counts"

if [ "${#failed[@]}" -gt 0 ]; then
	# `fail` can be 0 here, and that is not a contradiction: a file that stops
	# before its last assertion records no failed test and still returns a
	# failure. The count and the file list answer different questions, so the
	# message gives both.
	die "${#failed[@]} test file(s) did not pass: ${failed[*]}
     $fail of $((pass + fail)) test(s) that ran reported a failure.
     Each FAIL line above names what the test wanted and what it got.
     To run one file alone:  just test <part of its name>"
fi

info "$pass test(s) passed in ${#files[@]} file(s)"
