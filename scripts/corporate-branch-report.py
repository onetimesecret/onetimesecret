#!/usr/bin/env python3
"""
corporate-branch-report.py - Branch status report with fork detection

"Per my last commit, please find attached the synergistic branch metrics."

Usage: ./scripts/corporate-branch-report.py [options] [base-branch]

Options:
  --worktrees    Only show branches checked out in worktrees
  --help         Show this help message

Arguments:
  base-branch    Branch to compare against (default: develop)

Requirements:
  pip install rich GitPython
"""

import argparse
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field

try:
    import git
    from git import Repo
except ImportError:
    print("Please install GitPython: pip install GitPython", file=sys.stderr)
    sys.exit(1)

try:
    from rich.console import Console
    from rich.table import Table
    from rich.text import Text
    from rich import box
except ImportError:
    print("Please install rich: pip install rich", file=sys.stderr)
    sys.exit(1)

# Use actual terminal width if available, otherwise default to 160
term_width = shutil.get_terminal_size((160, 24)).columns
console = Console(width=max(term_width, 140))


@dataclass
class Branch:
    name: str
    commit: "git.Commit"
    ahead: int = 0
    behind: int = 0
    base_name: str = ""
    pr: str = "-"
    forked_from: str = ""
    subsumed_by: str = ""
    in_worktree: bool = False
    is_current: bool = False
    commits_ahead: list = field(default_factory=list)  # List of commit SHAs ahead of base (oldest first)

    @property
    def is_stale(self) -> bool:
        return self.behind > 0

    @property
    def is_subsumed(self) -> bool:
        return bool(self.subsumed_by)

    @property
    def should_dim(self) -> bool:
        return self.is_stale or self.is_subsumed

    @property
    def display_forked_from(self) -> str:
        return self.forked_from or self.base_name

    @property
    def latest_hash(self) -> str:
        return self.commit.hexsha[:4]

    @property
    def latest_msg(self) -> str:
        return self.commit.message.split('\n')[0][:36]

    @property
    def push_timestamp(self) -> int:
        return self.commit.committed_date


def run(cmd: str, default: str = "") -> str:
    """Run a shell command and return stdout, or default on error."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip() if result.returncode == 0 else default
    except (subprocess.TimeoutExpired, Exception):
        return default


def format_short_time(timestamp: int) -> str:
    """Convert unix timestamp to short relative time (1h, 2d, 5m)."""
    if timestamp == 0:
        return "?"
    diff = int(time.time()) - timestamp
    if diff < 0:
        return "0s"
    if diff < 60:
        return f"{diff}s"
    if diff < 3600:
        return f"{diff // 60}m"
    if diff < 86400:
        return f"{diff // 3600}h"
    return f"{diff // 86400}d"


def get_worktrees(repo: Repo) -> dict[str, str]:
    """Return dict of branch_name -> worktree_path."""
    worktrees = {}
    output = run("git worktree list")
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2].startswith('[') and parts[2].endswith(']'):
            branch = parts[2][1:-1]
            if branch and branch != "(detached":
                worktrees[branch] = parts[0]
    return worktrees


def get_commits_between(repo: Repo, base: str, head: str) -> list[str]:
    """Get list of commit SHAs between base and head (commits in head but not in base).

    Returns commits in oldest-first order to match bash script's prefix-based
    subsumption detection (where b1 is subsumed by b2 if b1's commits are a
    prefix of b2's commits).
    """
    try:
        # iter_commits returns newest-first, so reverse for oldest-first
        commits = [commit.hexsha for commit in repo.iter_commits(f"{base}..{head}")]
        commits.reverse()
        return commits
    except git.GitCommandError:
        return []


def resolve_base_name(repo: Repo, commit: "git.Commit") -> str:
    """Resolve a commit to branch name, tag name, or short hash."""
    commit_sha = commit.hexsha

    # Check if any branch points to this commit
    for ref in repo.heads:
        try:
            if ref.commit.hexsha == commit_sha:
                return ref.name
        except (ValueError, git.GitCommandError):
            continue  # Skip invalid refs

    # Check tags
    for tag in repo.tags:
        try:
            if tag.commit.hexsha == commit_sha:
                return tag.name
        except (ValueError, git.GitCommandError):
            continue

    return commit_sha[:7]


def collect_branches(repo: Repo, base_branch: str, worktrees_only: bool) -> list[Branch]:
    """Collect all branch data using GitPython."""
    worktrees = get_worktrees(repo)
    current = repo.active_branch.name if not repo.head.is_detached else ""

    try:
        base_commit = repo.commit(base_branch)
    except git.BadName:
        console.print(f"[red]Error: Base branch '{base_branch}' not found[/red]")
        sys.exit(1)

    branches = []

    for ref in repo.heads:
        name = ref.name
        if name == base_branch:
            continue

        if worktrees_only and name not in worktrees:
            continue

        # Get commits ahead/behind
        commits_ahead = get_commits_between(repo, base_branch, name)
        ahead = len(commits_ahead)

        if ahead == 0:
            continue

        commits_behind = get_commits_between(repo, name, base_branch)
        behind = len(commits_behind)

        # Get merge base
        try:
            merge_bases = repo.merge_base(ref.commit, base_commit)
            if merge_bases:
                base_name = resolve_base_name(repo, merge_bases[0])
            else:
                base_name = "unknown"
        except git.GitCommandError:
            base_name = "unknown"

        # Get PR (still use gh cli for this)
        pr = run(f"gh pr list --head {name} --json number --jq '.[0].number // empty'")
        pr = f"#{pr}" if pr else "-"

        branch = Branch(
            name=name,
            commit=ref.commit,
            ahead=ahead,
            behind=behind,
            base_name=base_name,
            pr=pr,
            in_worktree=name in worktrees,
            is_current=name == current,
            commits_ahead=commits_ahead,
        )
        branches.append(branch)

    return branches


def is_prefix(shorter: list, longer: list) -> bool:
    """Check if shorter list is a prefix of longer list."""
    if len(shorter) >= len(longer):
        return False
    return longer[:len(shorter)] == shorter


def detect_subsumption(branches: list[Branch]) -> None:
    """
    Detect which branches are subsumed by others using commit prefix matching.

    A branch B1 is subsumed by B2 if:
    - B1's commits are a prefix of B2's commits (b2 branched from b1's tip)
    - B1 has fewer commits than B2
    - We find the SMALLEST such B2 (immediate parent)

    This matches the bash script's behavior where subsumption represents
    linear history (b2 was branched from the tip of b1).
    """
    # Only consider branches that are 0 behind (clean lineage from base)
    clean_branches = [b for b in branches if b.behind == 0 and b.commits_ahead]

    for b1 in clean_branches:
        # Find all branches whose commits start with b1's commits (b1 is a prefix)
        subsumers = []
        for b2 in clean_branches:
            if b1.name == b2.name:
                continue
            # b2 subsumes b1 if b1's commits are a prefix of b2's commits
            if is_prefix(b1.commits_ahead, b2.commits_ahead):
                subsumers.append(b2)

        if subsumers:
            # Pick the smallest subsumer (immediate parent in the chain)
            immediate_parent = min(subsumers, key=lambda x: len(x.commits_ahead))
            b1.subsumed_by = immediate_parent.name

            # Set forked_from on the parent (track the largest child)
            current_fork = immediate_parent.forked_from
            if not current_fork:
                immediate_parent.forked_from = b1.name
            else:
                # Find the current fork branch and compare
                current_fork_branch = next((b for b in branches if b.name == current_fork), None)
                if current_fork_branch and len(b1.commits_ahead) > len(current_fork_branch.commits_ahead):
                    immediate_parent.forked_from = b1.name


def get_fork_age(branch: Branch, branches: list[Branch]) -> int:
    """Get timestamp of fork point for age calculation."""
    fork_name = branch.forked_from or branch.base_name
    for b in branches:
        if b.name == fork_name:
            return b.push_timestamp
    # If not a branch, get commit timestamp via subprocess
    ts = run(f"git log -1 --format='%ct' {fork_name}", "0")
    return int(ts) if ts else 0


def build_subsumption_tree(branch_name: str, branches: list[Branch]) -> str:
    """Recursively build nested subsumption string."""
    # Find all branches directly subsumed by this one
    direct = [b.name for b in branches if b.subsumed_by == branch_name]
    if not direct:
        return ""

    parts = []
    for d in direct:
        nested = build_subsumption_tree(d, branches)
        parts.append(d + (" " + nested if nested else ""))

    return "← [" + " ".join(parts) + "]"


def print_table(branches: list[Branch], all_branches: list[Branch]) -> None:
    """Print the main branch table using rich."""
    table = Table(box=box.SIMPLE, show_header=True, header_style="bold", expand=False)

    table.add_column("Branch", no_wrap=True)
    table.add_column("-/+", justify="right", no_wrap=True)
    table.add_column("Forked From", no_wrap=True)
    table.add_column("Age", justify="right", no_wrap=True)
    table.add_column("Pushed", justify="right", no_wrap=True)
    table.add_column("Latest Commit", no_wrap=True)
    table.add_column("PR", no_wrap=True)

    for b in branches:
        # Prefix: worktree and/or stale indicator
        if b.in_worktree and b.is_stale:
            prefix = "⚠️ 🌳 "
        elif b.in_worktree:
            prefix = "🌳 "
        elif b.is_stale:
            prefix = "⚠️  "
        else:
            prefix = "   "

        display_name = (prefix + b.name)[:28] + (" *" if b.is_current else "")
        diff = f"{b.behind}/{b.ahead}"
        forked = b.display_forked_from[:20]
        age = format_short_time(get_fork_age(b, all_branches))
        pushed = format_short_time(b.push_timestamp)
        latest = f"{b.latest_hash} {b.latest_msg}"[:36]

        style = "dim" if b.should_dim else None

        table.add_row(
            Text(display_name, style=style),
            Text(diff, style=style),
            Text(forked, style=style),
            Text(age, style=style),
            Text(pushed, style=style),
            Text(latest, style=style),
            Text(b.pr, style=style),
        )

    console.print(table)


def print_merge_order(branches: list[Branch]) -> None:
    """Print suggested merge order (canonical branches only)."""
    console.print("\n[bold]Suggested Merge Order[/bold] [dim](fewest commits first)[/dim]\n")

    # Filter to ready branches (0 behind) that aren't subsumed
    ready = [b for b in branches if b.behind == 0 and not b.is_subsumed]
    ready.sort(key=lambda x: x.ahead)

    if not ready:
        console.print("  No branches ready to merge (all are behind or subsumed)")
        return

    table = Table(box=None, show_header=False, padding=(0, 1), expand=False)
    table.add_column("#", justify="right", width=3, no_wrap=True)
    table.add_column("PR", width=6, no_wrap=True)
    table.add_column("Branch", no_wrap=True)
    table.add_column("+", justify="right", no_wrap=True)
    table.add_column("Includes", no_wrap=True)

    for i, b in enumerate(ready, 1):
        pr = b.pr if b.pr != "-" else ""
        tree = build_subsumption_tree(b.name, branches)

        table.add_row(
            f"{i}.",
            pr,
            b.name,
            f"+{b.ahead}",
            tree or "",
        )

    console.print(table)


def main():
    parser = argparse.ArgumentParser(
        description="Branch status report with fork detection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("base_branch", nargs="?", default="develop",
                        help="Branch to compare against (default: develop)")
    parser.add_argument("--worktrees", action="store_true",
                        help="Only show branches checked out in worktrees")
    args = parser.parse_args()

    console.print(f"[bold]Corporate Branch Report[/bold] [dim](base: {args.base_branch})[/dim]\n")

    try:
        repo = Repo(".", search_parent_directories=True)
    except git.InvalidGitRepositoryError:
        console.print("[red]Error: Not a git repository[/red]")
        sys.exit(1)

    branches = collect_branches(repo, args.base_branch, args.worktrees)

    if not branches:
        console.print(f"  No branches ahead of {args.base_branch}")
        if args.worktrees:
            console.print("  (filtered to worktrees only)")
        return

    detect_subsumption(branches)

    # Sort by commits ahead
    branches.sort(key=lambda x: x.ahead)

    print_table(branches, branches)
    print_merge_order(branches)


if __name__ == "__main__":
    main()
