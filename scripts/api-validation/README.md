# V1 API Validation Tooling

Validates backward compatibility of the OTS V1 API between v0.23.6 (baseline) and v0.24.0 (candidate). The scripts capture live API responses from both versions, diff them structurally, and cross-reference Zod schemas against Ruby response hashes.

## Prerequisites

- bash, curl, jq
- Node.js + npx (for TypeScript scripts)
- Two running OTS instances: one v0.23.6, one v0.24.0

## Setup

1. Start a v0.23.6 instance (e.g. `localhost:3000`)
2. Start a v0.24.0 instance (e.g. `localhost:3001`)
3. Have API credentials (username + API token) for both instances
4. Install TypeScript dependencies:
   ```bash
   cd scripts/api-validation/bin
   npm install
   ```

## Quick Start

```bash
cd scripts/api-validation/bin
./run-all.sh http://localhost:3000 http://localhost:3001 user@example.com apitoken123
```

## Individual Scripts

All scripts live in `bin/`:

| Script | Description |
|--------|-------------|
| `v1-capture.sh` | Captures V1 API request/response pairs from a running instance |
| `v1-diff.sh` | Compares two capture runs and produces a structured diff report |
| `v1-schema-extract.ts` | Extracts and compares V1 API response schemas |
| `v1-zod-diff.ts` | Extracts Zod schemas vs Ruby response hashes from local git refs |

## Output Structure

```
captures/
  v0.23.6/<timestamp>/*.json
  v0.24.0/<timestamp>/*.json
diffs/
  capture-diff.json
  schema-comparison.json
  zod-ruby-diff.json
```

## Known Caveats

- The PDF checklist (`v024-api-validation-checklist.pdf`) references v0.23.4 throughout; the actual baseline is v0.23.6.
- The checklist Section 9 says to run `npx tsc v1-schema-extract.ts && node dist/v1-schema-extract.js`, but the scripts use `tsx` shebangs and should be run with `npx tsx <script>` directly.
- The schema comparison in `v1-schema-extract.ts` uses hand-authored reference schemas; cross-check against actual captures.
