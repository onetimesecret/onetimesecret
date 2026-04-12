#!/usr/bin/env python3
"""
Two updates to translation_issues in locales/db/tasks.db:
1. Reframe _guidance.context task descriptions as "restore correct structure"
2. Set exec_order tiers so structural fixes run before content/style fixes
"""

import sqlite3
import re
from pathlib import Path

DB = Path(__file__).parent.parent.parent.parent / "locales/db/tasks.db"

# exec_order tiers (lower = fix first within a locale)
TIER_STRUCTURAL   = 10  # Wrong key shape: _guidance.context flat keys, skip:"" fixes
TIER_SECURITY     = 20  # OWASP violations: timing/attempt count disclosure
TIER_ENCODING     = 30  # Garbled text, Cyrillic char mixups
TIER_MISSING      = 40  # Keys absent from locale
TIER_FORMALITY    = 50  # Whole-locale register wrong (de_AT Sie, pt_PT tu)
TIER_PLURAL       = 60  # Wrong plural forms
TIER_TERMINOLOGY  = 70  # Wrong word choices
TIER_TONE         = 80  # Exclamation marks, voice
TIER_CLEANUP      = 90  # Missing source_hash, guide tasks, everything else


def classify_tier(row: sqlite3.Row) -> int:
    desc = (row["description"] or "").lower()
    issue_type = row["issue_type"]

    # Structural: _guidance.context as flat key, or skip:"" metadata defect
    if "_guidance.context" in desc or 'skip": ""' in desc or "skip: \"\"" in desc or "skip:\"\"" in desc:
        return TIER_STRUCTURAL
    if "skip: true" in desc and ("guidance" in desc or "metadata" in desc):
        return TIER_STRUCTURAL

    # Security: OWASP lockout/timing/attempt disclosure
    if any(p in desc for p in ["15 minut", "15 minute", "10 minut", "attempt", "locked_until",
                                 "lockout", "owasp", "timing", "attempt count", "attempt_remaining",
                                 "attempts_remaining", "magic_link.linkexpiresin"]):
        return TIER_SECURITY

    # Encoding
    if issue_type == "encoding" or any(p in desc for p in ["cyrillic", "garbled", "encoding", "mojibake"]):
        return TIER_ENCODING

    # Missing
    if issue_type == "missing":
        return TIER_MISSING

    # Formality / register
    if issue_type == "formality":
        return TIER_FORMALITY

    # Pluralization
    if issue_type == "pluralization":
        return TIER_PLURAL

    # Terminology
    if issue_type == "terminology":
        return TIER_TERMINOLOGY

    # Tone
    if issue_type == "tone":
        return TIER_TONE

    return TIER_CLEANUP


# Phrases that signal "remove this key" framing — to be replaced
REMOVE_PHRASES = [
    r"should not exist as a (separate|standalone|top-level|spurious) (translatable )?entry",
    r"(spurious|extra|unwanted) (top-level |flat )?(key|entry|translatable entry)",
    r"does not exist in the EN source as a (separate|standalone|top-level) key",
    r"(remove|delete) (the|this) (key|entry)",
    r"this key is a guidance.metadata key that should not (be there|exist)",
    r"is a structural defect",
]

RESTORE_PREFIX = (
    "Restore correct structure: the `{key}` flat key is a harmonization artifact — "
    "remove it and ensure the parent `{parent}` entry exists with `skip: true` and "
    "`context` as a property (matching EN source). "
)

KNOWN_GUIDANCE_KEYS = [
    "web.auth.security._guidance.context",
    "web.auth.sessions._guidance.context",
    "web.auth.verify._guidance.context",
]


def make_restore_prefix(description: str) -> str | None:
    """Return a 'restore correct structure' prefix if this is a _guidance.context task."""
    for key in KNOWN_GUIDANCE_KEYS:
        if key in description:
            parent = key.rsplit(".", 1)[0]  # strip .context
            return RESTORE_PREFIX.format(key=key, parent=parent)
    return None


def reframe_description(description: str) -> str | None:
    """
    If this description frames the task as 'remove key', prepend 'restore correct structure'
    and return updated text. Return None if no change needed.
    """
    if "_guidance.context" not in description:
        return None

    prefix = make_restore_prefix(description)
    if not prefix:
        return None

    # Already reframed — don't double-prefix
    if description.startswith("Restore correct structure"):
        return None

    return prefix + description


def main(dry_run: bool = False):
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    rows = db.execute(
        "SELECT id, description, issue_type, exec_order FROM translation_issues WHERE status = 'open'"
    ).fetchall()

    desc_updates = []
    order_updates = []

    for row in rows:
        # Description reframing
        new_desc = reframe_description(row["description"])
        if new_desc:
            desc_updates.append((new_desc, row["id"]))

        # exec_order
        tier = classify_tier(row)
        if tier != row["exec_order"]:
            order_updates.append((tier, row["id"]))

    print(f"Description updates: {len(desc_updates)}")
    print(f"exec_order updates:  {len(order_updates)}")

    if dry_run:
        print("\n--- Sample description updates (first 3) ---")
        for new_desc, id_ in desc_updates[:3]:
            print(f"  id={id_}: {new_desc[:120]}...")
        print("\n--- exec_order tier distribution ---")
        tier_counts: dict[int, int] = {}
        for tier, _ in order_updates:
            tier_counts[tier] = tier_counts.get(tier, 0) + 1
        for tier in sorted(tier_counts):
            label = {10:"structural", 20:"security", 30:"encoding", 40:"missing",
                     50:"formality", 60:"plural", 70:"terminology", 80:"tone", 90:"cleanup"}.get(tier, "?")
            print(f"  {tier} ({label}): {tier_counts[tier]}")
        return

    db.executemany("UPDATE translation_issues SET description = ?, updated_at = datetime('now') WHERE id = ?", desc_updates)
    db.executemany("UPDATE translation_issues SET exec_order = ?, updated_at = datetime('now') WHERE id = ?", order_updates)
    db.commit()

    total = db.execute("SELECT COUNT(*) FROM translation_issues WHERE status='open'").fetchone()[0]
    print(f"Done. {total} open issues total.")
    db.close()


if __name__ == "__main__":
    import sys
    main(dry_run="--dry-run" in sys.argv)
