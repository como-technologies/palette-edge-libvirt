#!/usr/bin/env bash
# Report how long each step of the end to end job really took.
#
# This repository used to publish a table of measured times. It went out of
# date the first time the pinned packs changed: an add-on profile alone doubled
# `cluster-up`, and nothing in `just lint` could notice, because a number in a
# document is not testable. A measurement is true of the day it was made.
#
# The end to end job builds a whole cluster on every push to `main` and every
# night, so the pipeline already holds a measurement of the CURRENT pins, made
# on the reference workstation. This reads it. There is no table to maintain,
# and the answer is never stale.
#
# It reads and changes nothing. `gh` supplies the credentials, so this needs no
# key of its own.
#
# Env: CI_RUNS     how many successful runs to read (default 3)
#      CI_WORKFLOW which workflow (default e2e.yml)
#
#   ci-times.sh
#   CI_RUNS=10 ci-times.sh

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

runs="${CI_RUNS:-3}"
workflow="${CI_WORKFLOW:-e2e.yml}"

need python3
command -v gh >/dev/null 2>&1 ||
	die "the GitHub CLI is not installed, and the run history is in GitHub.
     Install it:  https://cli.github.com
     Then:        gh auth login"

# `command gh`, never a bare `gh`. An interactive shell function of that name is
# exported into child shells, and one that reads GH_REPO with no default aborts
# under `set -u` -- silently, when the standard error is redirected.
command gh auth status >/dev/null 2>&1 ||
	die "the GitHub CLI holds no credentials. Run: gh auth login"

# Only the runs that finished. A failed run measures the step that failed and
# nothing after it, and a mean over those describes no build that happened.
ids="$(command gh run list --workflow "$workflow" --status success \
	--limit "$runs" --json databaseId --jq '.[].databaseId' 2>/dev/null || true)"

[ -n "$ids" ] || die "no successful '$workflow' run to read.
     The job builds a cluster on each push to main and every night.
     To see what there is:  gh run list --workflow $workflow
     To start one now:      gh workflow run $workflow"

info "the last $(printf '%s\n' "$ids" | wc -l) successful $workflow run(s)"

# One request for each run. The steps of a job carry started_at and
# completed_at, so the duration of a step is a subtraction and not an estimate.
bodies="$(mktemp -d)"
trap 'rm -rf "$bodies"' EXIT

for id in $ids; do
	command gh api "repos/{owner}/{repo}/actions/runs/$id/jobs" \
		>"$bodies/$id.json" 2>/dev/null ||
		warn "cannot read the jobs of run $id, so it is not in the table"
done

python3 - "$bodies" <<'PY'
import datetime, glob, json, os, sys

def seconds(start, end):
    if not start or not end:
        return None
    fmt = "%Y-%m-%dT%H:%M:%SZ"
    return (datetime.datetime.strptime(end, fmt)
            - datetime.datetime.strptime(start, fmt)).total_seconds()

# The order of the steps is the order of the job, so the table reads as the
# build runs. A step that one run skipped keeps its place.
order, rows = [], {}
files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=os.path.getmtime)
if not files:
    sys.exit("error: no run was readable")

for column, path in enumerate(files):
    with open(path) as f:
        data = json.load(f)
    for job in data.get("jobs") or []:
        for step in job.get("steps") or []:
            name = step.get("name") or "-"
            took = seconds(step.get("started_at"), step.get("completed_at"))
            if took is None:
                continue
            if name not in rows:
                order.append(name)
                rows[name] = {}
            rows[name][column] = took

count = len(files)
width = max([len(n) for n in order] + [4])

def clock(value):
    # Under a minute the seconds are the useful number. Over it, nobody reads
    # 1232s as twenty minutes.
    if value < 60:
        return "%.0fs" % value
    return "%dm%02ds" % (value // 60, value % 60)

header = "  {:<{w}}".format("step", w=width)
for i in range(count):
    header += "  {:>8}".format("run %d" % (i + 1))
header += "  {:>9}".format("mean")
print(header)
print("  " + "-" * (width + count * 10 + 11))

total = [0.0] * count
for name in order:
    line = "  {:<{w}}".format(name, w=width)
    values = []
    for i in range(count):
        took = rows[name].get(i)
        if took is None:
            line += "  {:>8}".format("-")
        else:
            line += "  {:>8}".format(clock(took))
            total[i] += took
            values.append(took)
    line += "  {:>9}".format(clock(sum(values) / len(values)) if values else "-")
    print(line)

line = "  {:<{w}}".format("whole job", w=width)
for i in range(count):
    line += "  {:>8}".format(clock(total[i]))
line += "  {:>9}".format(clock(sum(total) / count))
print("  " + "-" * (width + count * 10 + 11))
print(line)
PY
