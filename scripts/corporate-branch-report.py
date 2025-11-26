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
  pip install rich
"""

import argparse
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass

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
    ahead: int = 0
    behind: int = 0
    base_name: str = ""  # merge-base branch/tag/hash
    pr: str = "-"
    latest_hash: str = ""
    latest_msg: str = ""
    push_timestamp: int = 0
    forked_from: str = ""  # detected fork point
    subsumed_by: str = ""  # branch that contains this one
    in_worktree: bool = False
    is_current: bool = False

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


def get_worktrees() -> dict[str, str]:
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


def get_branch_refs() -> dict[str, str]:
    """Return dict of commit_hash -> branch_name for all branches."""
    refs = {}
    output = run("git for-each-ref --format='%(objectname) %(refname:short)' refs/heads/")
    for line in output.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            refs[parts[0]] = parts[1]
    return refs


def get_tags() -> dict[str, str]:
    """Return dict of commit_hash -> tag_name."""
    tags = {}
    output = run("git for-each-ref --format='%(objectname) %(refname:short)' refs/tags/")
    for line in output.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            tags[parts[0]] = parts[1]
    return tags


def resolve_base_name(commit: str, branch_refs: dict, tags: dict) -> str:
    """Resolve a commit to branch name, tag name, or short hash."""
    if commit in branch_refs:
        return branch_refs[commit]
    if commit in tags:
        return tags[commit]
    return commit[:7] if commit else "unknown"


def collect_branches(base_branch: str, worktrees_only: bool) -> list[Branch]:
    """Collect all branch data."""
    worktrees = get_worktrees()
    branch_refs = get_branch_refs()
    tags = get_tags()
    current = run("git rev-parse --abbrev-ref HEAD")

    branches = []
    branch_list = run("git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)'")

    for name in branch_list.splitlines():
        if name == base_branch:
            continue

        if worktrees_only and name not in worktrees:
            continue

        ahead = int(run(f"git rev-list --count {base_branch}..{name}", "0") or "0")
        if ahead == 0:
            continue

        behind = int(run(f"git rev-list --count {name}..{base_branch}", "0") or "0")

        # Get merge base
        merge_base = run(f"git merge-base {name} {base_branch}")
        base_name = resolve_base_name(merge_base, branch_refs, tags) if merge_base else "unknown"

        # Get PR
        pr = run(f"gh pr list --head {name} --json number --jq '.[0].number // empty'")
        pr = f"#{pr}" if pr else "-"

        # Get latest commit
        latest_hash = run(f"git log -1 --format='%h' {name}")[:4]
        latest_msg = run(f"git log -1 --format='%s' {name}")[:36]

        # Get push timestamp
        push_ts = int(run(f"git log -1 --format='%ct' {name}", "0") or "0")

        branch = Branch(
            name=name,
            ahead=ahead,
            behind=behind,
            base_name=base_name,
            pr=pr,
            latest_hash=latest_hash,
            latest_msg=latest_msg,
            push_timestamp=push_ts,
            in_worktree=name in worktrees,
            is_current=name == current,
        )
        branches.append(branch)

    return branches


def detect_subsumption(branches: list[Branch], base_branch: str) -> None:
    """Detect which branches are subsumed by others (commit prefix matching)."""
    # Only consider branches that are 0 behind (clean lineage from base)
    branch_commits: dict[str, str] = {}
    for b in branches:
        if b.behind == 0:
            commits = run(f"git rev-list --reverse {base_branch}..{b.name}")
            branch_commits[b.name] = commits

    # Find subsumption relationships - find the SMALLEST branch that contains each
    for b1 in branches:
        if b1.name not in branch_commits:
            continue
        commits1 = branch_commits[b1.name]
        if not commits1:
            continue

        # Find all branches that subsume b1, then pick the smallest (immediate parent)
        subsumers = []
        for b2 in branches:
            if b1.name == b2.name or b2.name not in branch_commits:
                continue
            commits2 = branch_commits[b2.name]
            if not commits2:
                continue

            # b1 is subsumed by b2 if b2's commits start with b1's commits
            if commits2.startswith(commits1) and b1.ahead < b2.ahead:
                subsumers.append(b2)

        if subsumers:
            # Pick the smallest subsumer (immediate parent in the chain)
            immediate_parent = min(subsumers, key=lambda x: x.ahead)
            b1.subsumed_by = immediate_parent.name
            # Set forked_from on the parent (track the largest child)
            if not immediate_parent.forked_from or b1.ahead > next(
                (x.ahead for x in branches if x.name == immediate_parent.forked_from), 0
            ):
                immediate_parent.forked_from = b1.name


def get_fork_age(branch: Branch, branches: list[Branch]) -> int:
    """Get timestamp of fork point for age calculation."""
    fork_name = branch.forked_from or branch.base_name
    # Find the branch or use base_name as fallback
    for b in branches:
        if b.name == fork_name:
            return b.push_timestamp
    # If not a branch, get commit timestamp
    ts = run(f"git log -1 --format='%ct' {fork_name}", "0")
    return int(ts) if ts else 0


def build_subsumption_tree(branch_name: str, branches: list[Branch]) -> str:
    """Recursively build nested subsumption string."""
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

    branches = collect_branches(args.base_branch, args.worktrees)

    if not branches:
        console.print(f"  No branches ahead of {args.base_branch}")
        if args.worktrees:
            console.print("  (filtered to worktrees only)")
        return

    detect_subsumption(branches, args.base_branch)

    # Sort by commits ahead
    branches.sort(key=lambda x: x.ahead)

    print_table(branches, branches)
    print_merge_order(branches)


if __name__ == "__main__":
    main()
