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
declare -A branch_commits=()
declare -A branch_prs=()
declare -A branch_focus=()

# Get all local branches
while IFS= read -r branch; do
  # Skip base branch itself
  [[ "$branch" == "$BASE_BRANCH" ]] && continue

  # If worktrees-only mode, skip branches not in worktrees
  if [[ "$WORKTREES_ONLY" == true && -z "${worktree_paths[$branch]:-}" ]]; then
    continue
  fi

  # Count commits ahead of base
  commits=$(git rev-list --count "$BASE_BRANCH..$branch" 2>/dev/null || echo "0")

  # Skip branches with no commits ahead
  [[ "$commits" == "0" ]] && continue

  branches+=("$branch")
  branch_commits["$branch"]="$commits"

  # Get associated PR (if any)
  pr=$(gh pr list --head "$branch" --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [[ -n "$pr" ]]; then
    branch_prs["$branch"]="#$pr"
  else
    branch_prs["$branch"]="-"
  fi

  # Get focus from most recent commit message
  focus=$(git log --oneline -1 "$branch" 2>/dev/null | sed 's/^[a-f0-9]* //' | cut -c1-30 || echo "Various")
  branch_focus["$branch"]="${focus:-"Various"}"

done < <(git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)')

# Check if we have any branches to show
if [[ ${#branches[@]} -eq 0 ]]; then
  echo "  No branches ahead of $BASE_BRANCH"
  if [[ "$WORKTREES_ONLY" == true ]]; then
    echo "  (filtered to worktrees only)"
  fi
  exit 0
fi

# Print table header
printf "| %-25s | %5s | %-32s | %-6s | %-2s |\n" "Branch" "Ahead" "Focus" "PR" "WT"
printf "|%s|%s|%s|%s|%s|\n" "$(printf '%.0s-' {1..27})" "$(printf '%.0s-' {1..7})" "$(printf '%.0s-' {1..34})" "$(printf '%.0s-' {1..8})" "$(printf '%.0s-' {1..4})"

# Sort by commits ahead (ascending) for suggested merge order
sorted_branches=()
for branch in "${branches[@]}"; do
  sorted_branches+=("${branch_commits[$branch]}|$branch")
done

IFS=$'\n' sorted=($(sort -t'|' -k1 -n <<< "${sorted_branches[*]}")); unset IFS

# Print rows
current_branch=$(git rev-parse --abbrev-ref HEAD)
for item in "${sorted[@]}"; do
  commits="${item%%|*}"
  branch="${item#*|}"

  # Mark current branch
  display_branch="$branch"
  [[ "$branch" == "$current_branch" ]] && display_branch="$branch *"

  # Worktree indicator
  wt_marker=""
  [[ -n "${worktree_paths[$branch]:-}" ]] && wt_marker="✓"

  printf "| %-25s | %5s | %-32s | %-6s | %-2s |\n" \
    "${display_branch:0:25}" \
    "$commits" \
    "${branch_focus[$branch]:0:32}" \
    "${branch_prs[$branch]}" \
    "$wt_marker"
done

echo ""
echo -e "${BOLD}Suggested Merge Order${RESET} ${DIM}(fewest commits first)${RESET}"
echo ""

order=1
for item in "${sorted[@]}"; do
  branch="${item#*|}"
  commits="${branch_commits[$branch]}"
  pr="${branch_prs[$branch]}"

  echo "  $order. $branch ($commits commits) $pr"
  ((order++))
done

echo ""
echo -e "${BOLD}File Overlap Analysis${RESET}"
echo ""

if [[ ${#branches[@]} -gt 1 ]]; then
  for ((i=0; i<${#branches[@]}; i++)); do
    for ((j=i+1; j<${#branches[@]}; j++)); do
      b1="${branches[$i]}"
      b2="${branches[$j]}"

      # Find common ancestor and check overlapping files
      ancestor=$(git merge-base "$b1" "$b2" 2>/dev/null || echo "$BASE_BRANCH")

      files1=$(git diff --name-only "$ancestor..$b1" 2>/dev/null | sort)
      files2=$(git diff --name-only "$ancestor..$b2" 2>/dev/null | sort)

      overlap=$(comm -12 <(echo "$files1") <(echo "$files2") 2>/dev/null | wc -l | xargs)

      if [[ "$overlap" -gt 0 ]]; then
        echo "  ⚠️  $b1 ↔ $b2: $overlap overlapping files"
      else
        echo "  ✓  $b1 ↔ $b2: No overlapping files"
      fi
    done
  done
else
  echo "  Only one branch ahead of $BASE_BRANCH"
fi
