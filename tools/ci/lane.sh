#!/usr/bin/env bash
#
# tools/ci/lane.sh — bin/ci lane <lane> [<overlay>]: run one lane, with an
# overlay from tests/lanes/overlays/ when one is named, the way the GitHub
# run-test-lane action does.
#
#   - The job owns the services, so the runner's autostart is off
#     (LANES_NO_AUTOSTART=1).
#   - The log capture profile: --capture-logs --log-console off --quiet. The
#     application log goes to tmp/lanes/<lane>/<overlay or base>/app.log and
#     the console transcript to last.log beside it; mail.log stays out of
#     artifacts, as on GitHub, because no log scrubbing has seen it.
#   - RSpec JSON results under tmp/rspec_<lane>[_<overlay>]_results*.json.
#
# The overlay is a second argument, not a flag, so a job can write
# `bin/ci lane $LANE $LANE_OVERLAY` and leave the variable empty.
#
# The lane's exit status is this command's. A red lane prints the services'
# state and logs before it exits, because the job's daemon is gone by
# after_script.
#
# BIN_CI_LANE_RUNNER replaces tests/lanes/run for the offline suite in
# tools/ci/tests/ only.
set -uo pipefail

# shellcheck source=tools/ci/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage="usage: bin/ci lane <lane> [<overlay>] (a directory under tests/lanes/, a file under tests/lanes/overlays/)"
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || ci_usage_error "$usage"
lane="$1"
overlay="${2:-}"
case "$lane" in
  '' | -* | */* | *[!A-Za-z0-9_-]*) ci_usage_error "not a lane name: ${lane}" ;;
esac
case "$overlay" in
  -* | */* | *[!A-Za-z0-9_-]*) ci_usage_error "not an overlay name: ${overlay}" ;;
esac

runner="${BIN_CI_LANE_RUNNER:-${CI_REPO_ROOT}/tests/lanes/run}"
cd "$CI_REPO_ROOT" || exit 1
unset GEM_HOME BUNDLE_APP_CONFIG
export LANES_NO_AUTOSTART=1
mkdir -p tmp
stem="${lane//-/_}"
args=("$lane" --capture-logs --log-console off --quiet)
label="$lane"
if [ -n "$overlay" ]; then
  stem="${stem}_${overlay//-/_}"
  args+=(--overlay "$overlay")
  label="${lane} (overlay ${overlay})"
fi
export RSPEC_OUTPUT_FILE="tmp/rspec_${stem}_results.json"

started=$SECONDS
status=0
"$runner" "${args[@]}" || status=$?
printf 'bin/ci lane %s: exit %s after %ss\n' "$label" "$status" "$((SECONDS - started))"

# Example counts per results file, read with the job's Ruby (no jq needed).
for results in "tmp/rspec_${stem}_results"*.json; do
  [ -s "$results" ] || continue
  ruby -rjson -e '
    s = JSON.parse(File.read(ARGV[0]))["summary"] or exit
    puts format("bin/ci lane: %s: %d examples, %d failures, %d pending",
                File.basename(ARGV[0]), s["example_count"], s["failure_count"], s["pending_count"])
  ' "$results" 2> /dev/null || printf 'bin/ci lane: %s is not complete JSON\n' "$results"
done

if [ "$status" -ne 0 ]; then
  ci_dump_services
fi
exit "$status"
