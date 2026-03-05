# Empty Translation Keys Report

2026-03-04 snapshot. Regenerate with the jq commands below.

## Runtime Mitigation

`messageResolver` in `src/i18n.ts` converts empty strings to `null`,
triggering English fallback. Empty keys are translation debt, not UI bugs.

## Tiers

| Tier | Locales | Empty Keys | Pattern |
|------|---------|------------|---------|
| Reference | en | 2 | `broadcast`, `secret_placeholder` |
| Tier 1 | es, ja, ko, de, da_DK, uk, pl, bg, pt_BR, el_GR, mi_NZ, de_AT, tr, it_IT, sv_SE, nl, fr_FR, fr_CA | 32–46 | Mostly `web.colonel.*` admin (23 keys) |
| Tier 2 | ru | 93 | colonel (51), footer (20), homepage/meta/labels |
| Tier 3 | da, zh, ar, vi, hu, he, cs, sl_SI, pt_PT, ca_ES | 606–721 | Harmonize scaffolding, all sections |

## Regenerate

Stats for a single locale:

```bash
jq -r '
  def count_empty:
    if type == "object" then
      reduce (to_entries[]) as $item (0; . + ($item.value | count_empty))
    elif . == "" then 1
    else 0
    end;
  [paths(scalars)] as $paths |
  length as $total |
  count_empty as $empty |
  {total: $total, empty: $empty, translated: ($total - $empty),
   completion: (($total-$empty)/$total*100 | . * 100 | round / 100)}
' src/locales/LANG.json
```

List empty key paths:

```bash
jq -r '
  paths(scalars) as $p |
  select(getpath($p) == "") |
  [$p[] | tostring] | join(".")
' src/locales/LANG.json
```
