# tools/host-seam/topology-lib.sh
#
# Sourced, never executed, so it carries no shebang.
# shellcheck shell=bash
#
# The parts of topology-probe.sh that decide what a row expects and how a
# response is graded, kept apart from the probe's curl requests so they can be
# loaded without sending anything:
#
#   - tools/host-seam/topology-probe.sh       sources this to run the matrix
#   - tools/host-seam/tests/topology-test.sh  sources this to test it
#   - apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb
#                                               calls spoof_accepted on what
#                                               the mounted stack answered
#
# Functions only: sourcing this defines them and sets TOPOLOGY_FILE, nothing
# else. bash 3.2 compatible, like the probe.

TOPOLOGY_FILE="${TOPOLOGY_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/topologies.psv}"

# The form two spellings of one host are compared in: lowercase, without a
# port and without the trailing dot of a fully qualified name.
normalize_host() {
  local host
  host="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  host="${host%%:*}"
  host="${host%.}"
  printf '%s' "$host"
}

# What a request resolving on `Host: <origin>` is expected to classify as,
# from the two hostnames alone: `canonical` when they are one host, else
# `invalid`. Right for an unregistered origin. An origin the application
# knows some other way (a subdomain of the canonical host such as www., a
# second canonical host, a registered custom domain) cannot be told from the
# names, which is why the probe measures an explicit --origin instead.
predicted_origin_strategy() { # <origin> <canonical>
  if [[ "$(normalize_host "$1")" == "$(normalize_host "$2")" ]]; then
    printf 'canonical'
  else
    printf 'invalid'
  fi
}

# Fill TOPOLOGIES from the matrix file, one `name|Host|Apx|XFH|XOH|Forwarded|
# expected` string per row with the placeholders replaced. The file is read
# as data and never executed. Fails on a row that does not have seven fields
# or still holds a placeholder.
load_topologies() { # <canonical> <custom> <origin> <evil> <origin_strategy> [file]
  local canonical="$1" custom="$2" origin="$3" evil="$4" origin_strategy="$5"
  local file="${6:-$TOPOLOGY_FILE}" line separators
  TOPOLOGIES=()

  if [[ ! -r "$file" ]]; then
    echo "FATAL: topology matrix not readable: ${file}" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '' | '#'*) continue ;;
    esac
    line="${line//\{canonical\}/$canonical}"
    line="${line//\{custom\}/$custom}"
    line="${line//\{origin_strategy\}/$origin_strategy}"
    line="${line//\{origin\}/$origin}"
    line="${line//\{evil\}/$evil}"
    separators="${line//[^|]/}"
    if [[ "${#separators}" -ne 6 || "$line" == *'{'* ]]; then
      echo "FATAL: malformed topology row in ${file}: ${line}" >&2
      return 1
    fi
    TOPOLOGIES+=("$line")
  done <"$file"

  if [[ "${#TOPOLOGIES[@]}" -eq 0 ]]; then
    echo "FATAL: no topology rows in ${file}" >&2
    return 1
  fi
}

# True when the evil host reached the display domain through a carrier the app
# does not read (Apx-Incoming-Host, a comma-joined X-Forwarded-Host). The
# application selects a single X-Forwarded-Host from a trusted peer
# (detect_host.rb FORWARDED_HEADERS; matrix spec rows F06, F07), so T9 and T10
# display the evil host and are graded on their `invalid` strategy.
spoof_accepted() { # <display_domain> <X-Forwarded-Host sent, or "-"> <evil>
  local display="$1" xfh="$2" evil="$3"
  [[ "$display" == "$evil" && "$xfh" != "$evil" ]]
}
