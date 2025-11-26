#!/usr/bin/env bash
#
# worktree-report.sh - Generate a report of git worktrees and their status
#
# Usage: ./scripts/worktree-report.sh [base-branch]
#
# Arguments:
#   base-branch  Branch to compare against (default: develop)
#
# Output: Markdown table with worktree status, PRs, and merge suggestions
#

set -euo pipefail

BASE_BRANCH="${1:-develop}"

# Colors for terminal (disabled if not tty)
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  RESET='\033[0m'
else
  BOLD=''
  RESET=''
fi

echo -e "${BOLD}Worktree Report${RESET} (base: $BASE_BRANCH)"
echo ""

# Collect worktree data
declare -a worktrees=()
declare -A branch_commits=()
declare -A branch_prs=()
declare -A branch_focus=()
declare -A branch_files=()

# Get all worktrees
while IFS= read -r line; do
  path=$(echo "$line" | awk '{print $1}')
  branch=$(echo "$line" | grep -oE '\[.*\]' | tr -d '[]')

  if [[ -n "$branch" && "$branch" != "(detached" ]]; then
    worktrees+=("$path|$branch")

    # Count commits ahead of base
    commits=$(git rev-list --count "$BASE_BRANCH..$branch" 2>/dev/null || echo "0")
    branch_commits["$branch"]="$commits"

    # Get associated PR (if any)
    pr=$(gh pr list --head "$branch" --json number --jq '.[0].number // empty' 2>/dev/null || true)
    if [[ -n "$pr" ]]; then
      branch_prs["$branch"]="#$pr"
    else
      branch_prs["$branch"]="-"
    fi

    # Get focus from most recent commit message (first line, trimmed)
    focus=$(git log --oneline -1 "$branch" 2>/dev/null | sed 's/^[a-f0-9]* //' | cut -c1-28 || echo "Various")
    branch_focus["$branch"]="${focus:-"Various"}"

    # Count changed files for overlap detection
    files=$(git diff --name-only "$BASE_BRANCH..$branch" 2>/dev/null | wc -l | xargs)
    branch_files["$branch"]="$files"
  fi
done < <(git worktree list)

# Print table header
printf "| %-45s | %-20s | %6s | %-30s | %-8s |\n" "Worktree" "Branch" "Ahead" "Focus" "PR"
printf "|%s|%s|%s|%s|%s|\n" "$(printf '%.0s-' {1..47})" "$(printf '%.0s-' {1..22})" "$(printf '%.0s-' {1..8})" "$(printf '%.0s-' {1..32})" "$(printf '%.0s-' {1..10})"

# Sort by commits ahead (descending) for suggested merge order
sorted_branches=()
for wt in "${worktrees[@]}"; do
  branch="${wt#*|}"
  sorted_branches+=("${branch_commits[$branch]}|$wt")
done

IFS=$'\n' sorted=($(sort -t'|' -k1 -n <<< "${sorted_branches[*]}")); unset IFS

# Print rows
current_branch=$(git rev-parse --abbrev-ref HEAD)
for item in "${sorted[@]}"; do
  wt="${item#*|}"
  path="${wt%|*}"
  branch="${wt#*|}"

  # Shorten path for display
  short_path="${path/#$HOME/~}"
  if [[ ${#short_path} -gt 45 ]]; then
    short_path="...${short_path: -42}"
  fi

  # Mark current worktree
  marker=""
  [[ "$branch" == "$current_branch" ]] && marker=" *"

  printf "| %-45s | %-20s | %6s | %-30s | %-8s |\n" \
    "$short_path$marker" \
    "$branch" \
    "${branch_commits[$branch]}" \
    "${branch_focus[$branch]:0:30}" \
    "${branch_prs[$branch]}"
done

echo ""
echo -e "${BOLD}Suggested Merge Order${RESET} (fewest commits first, fewer conflicts):"
echo ""

order=1
for item in "${sorted[@]}"; do
  wt="${item#*|}"
  branch="${wt#*|}"
  commits="${branch_commits[$branch]}"
  pr="${branch_prs[$branch]}"

  [[ "$commits" == "0" ]] && continue

  echo "  $order. $branch ($commits commits) ${pr}"
  ((order++))
done

echo ""
echo -e "${BOLD}File Overlap Analysis${RESET}:"
echo ""

# Check for overlapping files between branches
branches_with_commits=()
for wt in "${worktrees[@]}"; do
  branch="${wt#*|}"
  [[ "${branch_commits[$branch]}" != "0" ]] && branches_with_commits+=("$branch")
done

if [[ ${#branches_with_commits[@]} -gt 1 ]]; then
  for ((i=0; i<${#branches_with_commits[@]}; i++)); do
    for ((j=i+1; j<${#branches_with_commits[@]}; j++)); do
      b1="${branches_with_commits[$i]}"
      b2="${branches_with_commits[$j]}"

      # Find common ancestor and check overlapping files
      ancestor=$(git merge-base "$b1" "$b2" 2>/dev/null || echo "$BASE_BRANCH")

      files1=$(git diff --name-only "$ancestor..$b1" 2>/dev/null | sort)
      files2=$(git diff --name-only "$ancestor..$b2" 2>/dev/null | sort)

      overlap=$(comm -12 <(echo "$files1") <(echo "$files2") 2>/dev/null | wc -l | xargs)

      if [[ "$overlap" -gt 0 ]]; then
        echo "  ⚠️  $b1 ↔ $b2: $overlap overlapping files (potential conflicts)"
      else
        echo "  ✓  $b1 ↔ $b2: No overlapping files"
      fi
    done
  done
else
  echo "  Only one branch with commits ahead of $BASE_BRANCH"
fi
