# Archived Locale Scripts

Legacy i18n tooling kept for reference. These predate the current
`locales/content/<locale>/*.json` layout: they reference the old `src/locales/`
tree and an `en.json` base, and some call sibling scripts not kept in this
archive. Historical artifacts, not runnable tools. Current procedure:
`locales/README.md`.

## Contents

```
archive/
├── audit/
│   ├── analyze-by-file.js
│   ├── analyze-common-missing.js
│   ├── audit-translations.js
│   └── extract-i18n-manifest.py
├── harmonize/
│   ├── README.md
│   ├── check-missing-locale-files.sh
│   ├── github-action-harmonize.sh
│   └── harmonize-all-locale-files
├── translate/
│   └── pyproject.toml
└── validate/
    ├── README.md
    ├── check-locale-file
    └── check-locale-files
```

### `/audit`
- `audit-translations.js` - Scans `./src/locales`, writes `./translation-audit-report.txt`
- `analyze-by-file.js` / `analyze-common-missing.js` - Summarize that report (run audit first)
- `extract-i18n-manifest.py` - Cross-references `t()`/`$t()`/`I18n.t()` calls against locale JSON

### `/harmonize`
Structure sync against base English; see `harmonize/README.md`.
- `check-missing-locale-files.sh` - Reports/creates missing locale files (`--dry-run`, `--source LOCALE`)
- `harmonize-all-locale-files` - Wrapper; **incomplete**, calls a `harmonize-locale-file` not in this archive
- `github-action-harmonize.sh` - CI wrapper, same missing dependency

### `/validate`
Key-structure validation (values ignored; exit 0 = match, 1 = differences). See `validate/README.md`.
- `check-locale-file` - One file
- `check-locale-files` - All files

### `/translate`
- `pyproject.toml` - Orphaned manifest; the `claude-translate-locale.py` it described is gone.

Deps: `jq` (bash), `python3`, `node` (ES modules).
