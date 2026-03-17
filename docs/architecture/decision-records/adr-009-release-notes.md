---
id: "009"
status: accepted
title: "ADR-009: Two-Stream Release Notes"
---

## Status

Accepted

## Date

2026-03-16

## Context

The project produces release notes through two systems:

1. **Scriv** — human-written fragments in `changelog.d/`, collected into `CHANGELOG.rst` at release time.
2. **Release Drafter** — GitHub Action that auto-generates a GitHub Release body from merged PR titles and labels.

Both used the same Keep a Changelog categories (Added, Changed, Fixed, etc.) with no defined boundary between them. Contributors were unclear on whether both were required for a given PR.

Separately, Release Drafter's `Changed` category was mapped to domain labels (`frontend`, `backend`, `containers`, `i18n`) rather than intent labels. A PR labeled `bug` + `backend` appeared in both "Fixed" and "Changed" — release-drafter places PRs in every matching category, not first-match-wins.

## Decision

**Scriv owns the narrative; Release Drafter owns the inventory.** Scriv fragments describe what changed, why, and how to migrate — for developers upgrading. Release Drafter produces a complete PR index — for anyone scanning the GitHub Release.

**Release Drafter categories map to intent labels only** (`changed`, `deprecated`, `removed`, `feature`, `bug`, etc.). Domain labels (`frontend`, `backend`) remain useful for PR filtering but no longer drive release note sections. This eliminates cross-category duplication.

Alternatives considered:

- **Scriv's `github-release` to overwrite the draft entirely.** Loses the completeness safety net — PRs without fragments become invisible in releases.
- **Conventional commits generating both streams.** Requires commit message discipline across all contributors and produces changelogs that read like git logs.

## Trade-offs

- **We lose**: A single place for all release information — readers check GitHub Releases for completeness and `CHANGELOG.rst` for detail.
- **We gain**: Neither system tries to do the other's job. PR titles don't need to serve as changelog prose; trivial changes don't need fragments.
