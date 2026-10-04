# shellcheck shell=bash
# Package-private release evidence adapter. Sourcing it performs no I/O.
# The caller owns the supervisor PID; the supervisor owns Git and its watchdog.

# Must be launched asynchronously: that child shell is the supervisor itself,
# not a wrapper around another subshell whose PID would miss cancellation.
query_release_tags() {
  local remote="$1" work="$2" deadline=15
  local query_pid="" watchdog_pid="" status=0
  set -m
  trap 'trap "" INT TERM
        [[ -z "$query_pid" ]] || kill -KILL -- "-$query_pid" 2>/dev/null || true
        [[ -z "$watchdog_pid" ]] || kill -KILL -- "-$watchdog_pid" 2>/dev/null || true
        wait 2>/dev/null || true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Preserve configured transports, keys and proxies, but never prompt.
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false \
    SSH_ASKPASS=/usr/bin/false SSH_ASKPASS_REQUIRE=force \
    git ls-remote --tags --refs -- "$remote" 'refs/tags/v*' </dev/null &
  query_pid=$!
  (
    set +m
    trap - EXIT INT TERM
    sleep "$deadline"
    : > "$work/tag-query.timeout"
    kill -KILL -- "-$query_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!
  wait "$query_pid" || status=$?
  # A completion racing the deadline must not turn partial evidence into fact.
  [[ ! -f "$work/tag-query.timeout" ]] || status=124
  # Exit while the function's local PIDs still exist for the EXIT trap.
  exit "$status"
}

classify_release_tags() (
  # Deterministic policy: failed acquisition yields no usable evidence, even
  # when either input contains tags. No Git, network, or ambient configuration.
  local local_status="$1" remote_status="$2" local_tags="$3" remote_refs="$4"
  [[ "$local_status" == 0 && "$remote_status" == 0 ]] || return 1
  set -o pipefail
  export LC_ALL=C
  awk '
    FILENAME == ARGV[1] {
      if ($0 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print
      next
    }
    NF == 2 && $2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ {
      sub(/^refs\/tags\//, "", $2); print $2
    }
  ' "$local_tags" "$remote_refs" | sort -u
)
