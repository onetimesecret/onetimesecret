---
id: "047"
status: accepted
title: "ADR-047: Date Formatting for Documentation"
---

## Status

Accepted

## Date

2026-09-17

## Context

Dated planning documents need to sort chronologically in file lists without
making filenames harder to scan. Dates shown in documentation need to remain
readable when viewed outside a file list.

## Decision

Use `YYYY-MMDD` as the date prefix for dated planning-document filenames, for
example `2026-0917-authentication-release-workplan.md`.

Use `YYYY-MM-DD` for dates in documentation body text and metadata. A planning
document's filename uses its primary recorded date; later verification or
update dates do not rename it.
