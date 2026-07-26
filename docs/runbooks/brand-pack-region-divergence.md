# Per-Region Brand Divergence

## Overview

Symptom: branding renders wrong in one region but correct in others (e.g. the
v0.26.0 UK incident — brand files were byte-identical across CA/NZ/UK
containers, yet UK rendered NEUTRAL). Identical files rule out the filesystem,
so the cause is one of: config, `BRAND_*` env not reaching the container, or a
boot-time mount race.

Diagnostic tool (shipped in #3822):

- **CLI:** `bin/ots config brand` — human summary. Add `--json` for machine
  output. Exit codes: `0` clean, `2` broken checkout, `1`
  `fell_back_to_default` OR `boot_vs_live_mismatch`.
- **Colonel Admin:** System page → "Brand Diagnostics" section, backed by
  `GET /api/colonel/system/brand` (colonel-only).

## Key Field: `boot_vs_live_mismatch`

`true` means the brand volume mounted **after** boot: the frozen
`OT.conf['brand']` absorbed nothing at boot, while the pack resolves fine now.
A **restart** fixes it.

## Diagnosis

Run the diagnostic on **each affected container/region** and DIFF the output:

```bash
bin/ots config brand          # or --json
```

or open Colonel → System → Brand Diagnostics.

## Resolution

- **`boot_vs_live_mismatch = true`** → restart that instance. The pack is fine;
  boot just ran before the mount landed.

- **`fell_back_to_default = true`** with a non-default `brand_pack` /
  `brand_assets_dir` configured → the configured pack isn't resolving. Verify:
  1. The brand volume mount resolves **inside** the container. Roots are
     HOME-relative (e.g. `/app/etc/branding`).
  2. `BRAND_*` env actually reached the container — compare env vs config in the
     diagnostic output.

- **Broken checkout (exit `2`)** → the brand-pack resolver returned nothing
  (`resolved_dir` is nil): even the default pack is absent or unresolvable,
  indicating a broken image build or checkout. Rebuild the image / fix the
  mount. (A resolved pack that merely references missing assets does **not**
  trigger exit `2` — those assets are filtered out and `resolved_dir` stays
  non-nil, so the run exits `0` or `1`.)

## Prevention

- Treat a non-zero exit from `bin/ots config brand` as a deploy gate on
  brand-affecting changes.
- Confirm brand volumes mount before app boot in the container orchestration.
