#!/usr/bin/env bash
# Inputs: FILTER_AUTH, FORCE_AUTH (literal true/false), EVENT_NAME, LABELS_JSON
# (one JSON array of label-name strings). All four are required. No skip flags.
# Optional: GITHUB_OUTPUT and GITHUB_STEP_SUMMARY. Without GITHUB_OUTPUT, emit
# auth/reason on stdout so the same selector can be exercised locally.
set -euo pipefail

fail() {
  printf '::error::%s\n' "$1" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail 'Auth selection accepts environment inputs only, not command-line flags.'

# Validate before any override: forcing must not conceal broken detection.
for name in FILTER_AUTH FORCE_AUTH; do
  case "${!name-}" in
    true | false) ;;
    *) fail "$name must be the literal string true or false." ;;
  esac
done

# Slurp enforces exactly one JSON value; jq normally accepts a stream of values.
# Check shape before lookup so null, objects, or non-string entries cannot look
# like an absent ci:auth label. Never echo untrusted labels into workflow commands.
if ! label_auth="$(printf '%s' "${LABELS_JSON-}" | jq -er -s '
  if length == 1 and (.[0] | type == "array" and all(.[]; type == "string"))
  then (.[0] | index("ci:auth") != null | tostring)
  else error("expected one array of label-name strings")
  end
' 2>/dev/null)"; then
  fail 'LABELS_JSON must be one JSON array of label-name strings (jq is required).'
fi

# Push is unconditional: the caller controls its main/tag trigger restriction.
# Unknown events fail rather than silently turning coverage off.
case "${EVENT_NAME-}" in
  schedule | push | merge_group | workflow_dispatch)
    auth=true
    reason="event:$EVENT_NAME"
    ;;
  pull_request)
    if [[ "$FORCE_AUTH" == true ]]; then
      auth=true
      reason=force
    elif [[ "$label_auth" == true ]]; then
      auth=true
      reason=label:ci:auth
    elif [[ "$FILTER_AUTH" == true ]]; then
      auth=true
      reason=paths
    else
      auth=false
      reason=no-auth-changes
    fi
    ;;
  *) fail 'EVENT_NAME must be pull_request, schedule, push, merge_group, or workflow_dispatch.' ;;
esac

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'auth=%s\nreason=%s\n' "$auth" "$reason" >> "$GITHUB_OUTPUT"
else
  printf 'auth=%s\nreason=%s\n' "$auth" "$reason"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  # Markdown backticks are literal, not command substitutions.
  # shellcheck disable=SC2016
  printf '## Auth selection\n\n- auth: `%s`\n- reason: `%s`\n' \
    "$auth" "$reason" >> "$GITHUB_STEP_SUMMARY"
fi
