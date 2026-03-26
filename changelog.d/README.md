# Changelog Fragments

Fragment-based changelog managed by [Scriv](https://scriv.readthedocs.io/), following [Keep a Changelog](https://keepachangelog.com) and semver. Configuration: `changelog.d/scriv.ini`.

## When to Write a Fragment

Write a fragment when the change affects behavior, requires migration steps, or would surprise someone upgrading. Internal PRs (refactoring, CI, dependency bumps) don't need one — Release Drafter captures those automatically.

See [ADR-009](../docs/architecture/decision-records/adr-009-release-notes.md) for the rationale behind this two-stream model.

## Adding a Changelog Entry

```bash
scriv create                    # creates a fragment in changelog.d/
# edit the fragment, then:
git add changelog.d/*.rst
git commit
```

Optionally add a migrating guide in `docs/migrating/` — use existing guides there as a reference.

## Fragment Guidelines

- One fragment per change.
- Describe the *impact*, not the implementation. ("Fixed password reset for SSO users" not "Refactored `AuthManager`.")
- Reference issue/PR numbers — scriv auto-links them.
- AI assistance goes in its own fragment under the `AI Assistance` category.

### Categories

- **Added**: New features or capabilities.
- **Changed**: Changes to existing functionality.
- **Deprecated**: Soon-to-be removed features.
- **Removed**: Now removed features.
- **Fixed**: Bug fixes.
- **Security**: Security-related improvements.
- **Documentation**: Documentation improvements.
- **AI Assistance**: Significant AI assistance in the change.

## Release

```bash
scriv collect    # merges fragments into CHANGELOG.rst
```

Version is read from `lib/onetime/version.rb` via `scriv.ini`.
