#!/usr/bin/env python3
"""
Migrate QC issues from .claude/tasks/i18n-qc.db to locales/db/tasks.db
(translation_issues table).
"""

import sqlite3
import os
import re
import sys
from pathlib import Path

WORKTREE = Path(__file__).parent.parent.parent.parent
SOURCE_DB = WORKTREE / ".claude/tasks/i18n-qc.db"
DEST_DB = WORKTREE / "locales/db/tasks.db"


def extract_locale(title: str) -> str:
    """Extract locale code from title prefix like 'ar: ...' or 'fr_FR: ...'"""
    m = re.match(r'^([a-zA-Z]{2}(?:_[A-Z]{2})?|Policy)\s*:', title)
    if m:
        locale = m.group(1)
        return "en" if locale == "Policy" else locale
    return "unknown"


def extract_file(file_path: str | None) -> str | None:
    """Extract just the filename from a path like 'locales/content/ar/session-auth-extended.json:3'"""
    if not file_path:
        return None
    # Remove line number suffix
    path = file_path.split(":")[0].strip()
    return os.path.basename(path) if path else None


def infer_issue_type(title: str, description: str, category: str) -> str:
    """Infer translation_issues.issue_type from title/description/category."""
    text = (title + " " + description).lower()

    if category == "security":
        return "other"
    if category == "metadata":
        return "other"
    if category == "guide":
        return "other"

    # translation category — infer from content
    if re.search(r'\bplural|plurali[sz]|dual form|pipe form|three form', text):
        return "pluralization"
    if re.search(r'\bformali|register|sie\b|vous\b|você\b|tu-form|du-form|vi-form|formal address|informal', text):
        return "formality"
    if re.search(r'\bencoding|cyrillic|garbled|mojibake|unicode|utf', text):
        return "encoding"
    if re.search(r'\bmissing|absent|not present|does not exist|add.*key|key.*added', text):
        return "missing"
    if re.search(r'\btruncated|cut.?off|incomplete|too short', text):
        return "truncated"
    if re.search(r'\bgrammar|agreement|typo|spelling\b', text):
        return "grammar"
    if re.search(r'\brtl|right-to-left|bidirect', text):
        return "rtl"
    if re.search(r'\bvariable|placeholder|\{[a-z]|\%\{', text):
        return "placeholder"
    if re.search(r'\btone|exclamation|voice|casual|formal tone', text):
        return "tone"
    if re.search(r'\bterminol|glossary|word choice|hemmelighed|besked|geslo|senha|segreto\b', text):
        return "terminology"
    if re.search(r'\buntranslated|english source|english text|not translated', text):
        return "missing"
    if re.search(r'\bspurious|extra key|unwanted key|should not exist|live key', text):
        return "other"

    return "other"


def map_severity(priority: str, category: str) -> str:
    """Map P1/P2/P3 + category to critical/high/medium/low."""
    if priority == "P1":
        return "critical"
    if priority == "P2":
        return "high" if category == "security" else "medium"
    return "low"  # P3


def map_status(status: str) -> str:
    if status == "wontfix":
        return "wontfix"
    return "open"


def migrate(dry_run: bool = False):
    src = sqlite3.connect(SOURCE_DB)
    src.row_factory = sqlite3.Row

    dst = sqlite3.connect(DEST_DB)

    rows = src.execute("""
        SELECT t.id, t.priority, t.status, t.title, t.description,
               t.file_path, t.notes, c.slug as category
        FROM tasks t
        JOIN categories c ON t.category_id = c.id
        ORDER BY t.priority, t.id
    """).fetchall()

    print(f"Source tasks: {len(rows)}")

    inserts = []
    skipped = []
    for row in rows:
        locale = extract_locale(row["title"])
        file_ = extract_file(row["file_path"])
        issue_type = infer_issue_type(row["title"], row["description"], row["category"])
        severity = map_severity(row["priority"], row["category"])
        status = map_status(row["status"])
        description = row["description"].strip()

        inserts.append((
            locale,
            file_,
            None,           # key_path — not stored in source
            issue_type,
            severity,
            status,
            None,           # source_text
            None,           # current_text
            None,           # suggested_text
            description,
            "qc_agent",     # detected_by
        ))

    if dry_run:
        from collections import Counter
        type_counts = Counter(r[3] for r in inserts)
        sev_counts = Counter(r[4] for r in inserts)
        locale_counts = Counter(r[0] for r in inserts)
        print(f"\nIssue types: {dict(type_counts)}")
        print(f"Severities:  {dict(sev_counts)}")
        print(f"Locales:     {dict(sorted(locale_counts.items()))}")
        print(f"\nWould insert {len(inserts)} rows into translation_issues.")
        return

    dst.executemany("""
        INSERT INTO translation_issues
            (locale, file, key_path, issue_type, severity, status,
             source_text, current_text, suggested_text,
             description, detected_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, inserts)
    dst.commit()

    count = dst.execute("SELECT COUNT(*) FROM translation_issues").fetchone()[0]
    print(f"Inserted {len(inserts)} rows. translation_issues now has {count} rows.")

    src.close()
    dst.close()


if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv
    if dry_run:
        print("=== DRY RUN ===")
    migrate(dry_run=dry_run)
