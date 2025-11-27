#!/usr/bin/env bash
#
# corporate-branch-report.sh - Your quarterly branch status report
#
# "Per my last commit, please find attached the synergistic branch metrics."
#
# Usage: ./scripts/corporate-branch-report.sh [options] [base-branch]
#
# Options:
#   --worktrees    Only show branches checked out in worktrees
#   --help         Show this help message
#
# Arguments:
#   base-branch    Branch to compare against (default: develop)
#
# Output: Executive summary of branch status, PRs, and actionable merge insights
#

set -euo pipefail

# Parse arguments
WORKTREES_ONLY=false
BASE_BRANCH="develop"

while [[ $# -gt 0 ]]; do
  case $1 in
    --worktrees)
      WORKTREES_ONLY=true
      shift
      ;;
    --help|-h)
      head -18 "$0" | tail -16
      exit 0
      ;;
    *)
      BASE_BRANCH="$1"
      shift
      ;;
  esac
done

# Colors for terminal (disabled if not tty)
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  BOLD=''
  DIM=''
  RESET=''
fi

echo -e "${BOLD}Corporate Branch Report${RESET} ${DIM}(base: $BASE_BRANCH)${RESET}"
echo ""

# Collect worktree info first (to mark which branches are in worktrees)
declare -A worktree_paths=()
while IFS= read -r line; do
  path=$(echo "$line" | awk '{print $1}')
  branch=$(echo "$line" | grep -oE '\[.*\]' | tr -d '[]')
  if [[ -n "$branch" && "$branch" != "(detached" ]]; then
    worktree_paths["$branch"]="$path"
  fi
done < <(git worktree list)

# Collect branch data
declare -a branches=()
declare -A branch_ahead=()
declare -A branch_behind=()
declare -A branch_prs=()
declare -A branch_latest=()
declare -A branch_base=()
declare -A branch_base_age=()
declare -A branch_last_push=()

# Get all local branches
while IFS= read -r branch; do
  # Skip base branch itself
  [[ "$branch" == "$BASE_BRANCH" ]] && continue

  # If worktrees-only mode, skip branches not in worktrees
  if [[ "$WORKTREES_ONLY" == true && -z "${worktree_paths[$branch]:-}" ]]; then
    continue
  fi

  # Count commits ahead of base
  ahead=$(git rev-list --count "$BASE_BRANCH..$branch" 2>/dev/null || echo "0")

  # Skip branches with no commits ahead
  [[ "$ahead" == "0" ]] && continue

  # Count commits behind base
  behind=$(git rev-list --count "$branch..$BASE_BRANCH" 2>/dev/null || echo "0")

  # Get merge base (where branch diverged from base)
  merge_base=$(git merge-base "$branch" "$BASE_BRANCH" 2>/dev/null || echo "")
  if [[ -n "$merge_base" ]]; then
    # Check if merge base matches a branch tip (like develop)
    base_name=""
    for ref in $(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null); do
      ref_commit=$(git rev-parse "$ref" 2>/dev/null || echo "")
      if [[ "$ref_commit" == "$merge_base" ]]; then
        base_name="$ref"
        break
      fi
    done
    # Also check tags
    if [[ -z "$base_name" ]]; then
      base_name=$(git describe --tags --exact-match "$merge_base" 2>/dev/null || echo "")
    fi
    # Fall back to short hash
    if [[ -z "$base_name" ]]; then
      base_name=$(git rev-parse --short=7 "$merge_base" 2>/dev/null || echo "unknown")
    fi
  else
    base_name="unknown"
  fi

  branches+=("$branch")
  branch_ahead["$branch"]="$ahead"
  branch_behind["$branch"]="$behind"
  branch_base["$branch"]="$base_name"

  # Get associated PR (if any)
  pr=$(gh pr list --head "$branch" --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [[ -n "$pr" ]]; then
    branch_prs["$branch"]="#$pr"
  else
    branch_prs["$branch"]="-"
  fi

  # Get latest commit (short hash + message)
  latest_hash=$(git log -1 --format='%h' "$branch" 2>/dev/null | cut -c1-4 || echo "????")
  latest_msg=$(git log -1 --format='%s' "$branch" 2>/dev/null | cut -c1-40 || echo "unknown")
  branch_latest["$branch"]="${latest_hash} ${latest_msg}"

  # Get latest push date as unix timestamp for short format conversion
  branch_last_push["$branch"]=$(git log -1 --format='%ct' "$branch" 2>/dev/null || echo "0")

done < <(git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)')

# Check if we have any branches to show
if [[ ${#branches[@]} -eq 0 ]]; then
  echo "  No branches ahead of $BASE_BRANCH"
  if [[ "$WORKTREES_ONLY" == true ]]; then
    echo "  (filtered to worktrees only)"
  fi
  exit 0
fi

# For branches 0 behind, collect their commit hashes to find subsumption
declare -A branch_commits=()
declare -A branch_subsumed_by=()

for branch in "${branches[@]}"; do
  if [[ "${branch_behind[$branch]}" == "0" ]]; then
    # Get commit hashes this branch has ahead of base (oldest first for prefix matching)
    commits=$(git rev-list --reverse "$BASE_BRANCH..$branch" 2>/dev/null | tr '\n' ' ')
    branch_commits["$branch"]="$commits"
  fi
done

# Find which branches are subsumed by others (their commits are a prefix of a larger branch)
# Also track what each branch "branched from" (the largest branch it subsumes)
declare -A branch_forked_from=()

for b1 in "${!branch_commits[@]}"; do
  commits1="${branch_commits[$b1]}"
  [[ -z "$commits1" ]] && continue

  for b2 in "${!branch_commits[@]}"; do
    [[ "$b1" == "$b2" ]] && continue
    commits2="${branch_commits[$b2]}"
    [[ -z "$commits2" ]] && continue

    # Check if b1's commits are a prefix of b2's commits (b1 is subsumed by b2)
    if [[ "$commits2" == "$commits1"* && "${branch_ahead[$b1]}" -lt "${branch_ahead[$b2]}" ]]; then
      # b1 is subsumed by b2 (b2 contains all of b1's commits plus more)
      branch_subsumed_by["$b1"]="$b2"
      # b2 forked from b1 (track the largest/most recent one)
      current_fork="${branch_forked_from[$b2]:-}"
      if [[ -z "$current_fork" || "${branch_ahead[$b1]}" -gt "${branch_ahead[$current_fork]}" ]]; then
        branch_forked_from["$b2"]="$b1"
      fi
    fi
  done
done

# Function to convert unix timestamp to short relative time (1h, 2d, 5m)
format_short_time() {
  local timestamp="$1"
  local now=$(date +%s)
  local diff=$((now - timestamp))

  if [[ $diff -lt 60 ]]; then
    echo "${diff}s"
  elif [[ $diff -lt 3600 ]]; then
    echo "$((diff / 60))m"
  elif [[ $diff -lt 86400 ]]; then
    echo "$((diff / 3600))h"
  else
    echo "$((diff / 86400))d"
  fi
}

# Print table header
printf "| %-25s | %9s | %-20s | %5s | %6s | %-32s | %-6s |\n" "Branch" "-/+" "Forked From" "Age" "Pushed" "Latest Commit" "PR"
printf "|%s|%s|%s|%s|%s|%s|%s|\n" "$(printf '%.0s-' {1..27})" "$(printf '%.0s-' {1..11})" "$(printf '%.0s-' {1..22})" "$(printf '%.0s-' {1..7})" "$(printf '%.0s-' {1..8})" "$(printf '%.0s-' {1..34})" "$(printf '%.0s-' {1..8})"

# Sort by commits ahead (ascending) for suggested merge order
sorted_branches=()
for branch in "${branches[@]}"; do
  sorted_branches+=("${branch_ahead[$branch]}|$branch")
done

IFS=$'\n' sorted=($(sort -t'|' -k1 -n <<< "${sorted_branches[*]}")); unset IFS

# Print rows
current_branch=$(git rev-parse --abbrev-ref HEAD)
for item in "${sorted[@]}"; do
  ahead="${item%%|*}"
  branch="${item#*|}"
  behind="${branch_behind[$branch]}"

  # Build display branch with markers
  # Use fixed-width prefix: 🌳 worktree, ⚠️ stale (behind), or space
  is_stale=false
  if [[ -n "${worktree_paths[$branch]:-}" ]]; then
    if [[ "$behind" != "0" ]]; then
      prefix="⚠️ 🌳"  # Both stale and in worktree
      is_stale=true
    else
      prefix="🌳"
    fi
  elif [[ "$behind" != "0" ]]; then
    prefix="⚠️ "
    is_stale=true
  else
    prefix="  "
  fi

  display_branch="$branch"
  [[ "$branch" == "$current_branch" ]] && display_branch="$branch *"

  # Format -/+ column: right-align behind, left-align ahead with fixed width
  diff_display=$(printf "%4d/%-4d" "$behind" "$ahead")

  # Determine "Forked From" - use detected fork point if available, else merge-base
  forked_from="${branch_forked_from[$branch]:-${branch_base[$branch]}}"

  # Calculate age based on forked_from branch (time since fork point)
  if [[ -n "${branch_forked_from[$branch]:-}" ]]; then
    # Get timestamp of tip of forked_from branch
    fork_ts=$(git log -1 --format='%ct' "${branch_forked_from[$branch]}" 2>/dev/null || echo "0")
  else
    # Use merge-base timestamp
    fork_ts=$(git log -1 --format='%ct' "${branch_base[$branch]}" 2>/dev/null || echo "0")
  fi
  age_display=$(format_short_time "$fork_ts")

  # Format pushed time
  pushed_display=$(format_short_time "${branch_last_push[$branch]}")

  # Print with prefix separate to handle emoji width
  # Dim rows for branches that are subsumed OR stale (won't appear in Suggested Merge Order)
  if [[ -n "${branch_subsumed_by[$branch]:-}" || "$is_stale" == true ]]; then
    printf "${DIM}| %s %-22s | %9s | %-20s | %5s | %6s | %-32s | %-6s |${RESET}\n" \
      "$prefix" \
      "${display_branch:0:22}" \
      "$diff_display" \
      "${forked_from:0:20}" \
      "$age_display" \
      "$pushed_display" \
      "${branch_latest[$branch]:0:32}" \
      "${branch_prs[$branch]}"
  else
    printf "| %s %-22s | %9s | %-20s | %5s | %6s | %-32s | %-6s |\n" \
      "$prefix" \
      "${display_branch:0:22}" \
      "$diff_display" \
      "${forked_from:0:20}" \
      "$age_display" \
      "$pushed_display" \
      "${branch_latest[$branch]:0:32}" \
      "${branch_prs[$branch]}"
  fi
done

# Find the "canonical" branches (not subsumed by any other)
declare -A canonical_branches=()
for branch in "${branches[@]}"; do
  if [[ -z "${branch_subsumed_by[$branch]:-}" ]]; then
    canonical_branches["$branch"]=1
  fi
done

# Separate branches into ready-to-merge and stale (behind base)
declare -a ready_branches=()
declare -a stale_branches=()

for item in "${sorted[@]}"; do
  branch="${item#*|}"
  if [[ "${branch_behind[$branch]}" == "0" ]]; then
    ready_branches+=("$item")
  else
    stale_branches+=("$item")
  fi
done

# Function to recursively build nested subsumption string
build_subsumption_tree() {
  local target="$1"
  local -a direct=()

  # Find branches directly subsumed by target
  for other in "${branches[@]}"; do
    if [[ "${branch_subsumed_by[$other]:-}" == "$target" ]]; then
      direct+=("$other")
    fi
  done

  if [[ ${#direct[@]} -eq 0 ]]; then
    echo ""
    return
  fi

  # Build the nested string
  local result="← ["
  local first=true
  for d in "${direct[@]}"; do
    [[ "$first" != true ]] && result+=" "
    first=false
    result+="$d"
    # Recurse for nested subsumption
    local nested
    nested=$(build_subsumption_tree "$d")
    [[ -n "$nested" ]] && result+=" $nested"
  done
  result+="]"
  echo "$result"
}

echo ""
echo -e "${BOLD}Suggested Merge Order${RESET} ${DIM}(fewest commits first)${RESET}"
echo ""

if [[ ${#ready_branches[@]} -eq 0 ]]; then
  echo "  No branches ready to merge (all are behind $BASE_BRANCH)"
else
  order=1
  for item in "${ready_branches[@]}"; do
    branch="${item#*|}"
    ahead="${branch_ahead[$branch]}"
    pr="${branch_prs[$branch]}"

    # Only show canonical branches (not subsumed by any other)
    [[ -n "${branch_subsumed_by[$branch]:-}" ]] && continue

    # Build subsumption tree for this branch
    subsumption=$(build_subsumption_tree "$branch")

    # Format: index, PR, branch, (+added), subsumption
    pr_display="     "
    [[ "$pr" != "-" ]] && pr_display=$(printf "%-5s" "$pr")

    if [[ -n "$subsumption" ]]; then
      printf "  %d. %s %-20s (+%d)  %s\n" "$order" "$pr_display" "$branch" "$ahead" "$subsumption"
    else
      printf "  %d. %s %-20s (+%d)\n" "$order" "$pr_display" "$branch" "$ahead"
    fi
    ((order++))
  done
fi
