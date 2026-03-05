# Empty Translation Keys Report

2026-03-04 snapshot. Regenerate with the jq commands below.

## Runtime Mitigation

`messageResolver` in `src/i18n.ts` converts empty strings to `null`,
triggering English fallback. Empty keys are translation debt, not UI bugs.

## Per-Locale Counts

| Locale | Language | Empty | Tier |
|--------|----------|------:|------|
| en | English | 2 | reference |
| es | Spanish | 32 | 1 |
| ja | Japanese | 32 | 1 |
| ko | Korean | 32 | 1 |
| de | German | 33 | 1 |
| da_DK | Danish (DK) | 33 | 1 |
| uk | Ukrainian | 33 | 1 |
| pl | Polish | 33 | 1 |
| bg | Bulgarian | 33 | 1 |
| pt_BR | Portuguese (BR) | 33 | 1 |
| el_GR | Greek | 33 | 1 |
| mi_NZ | Maori | 34 | 1 |
| de_AT | Austrian German | 35 | 1 |
| tr | Turkish | 35 | 1 |
| it_IT | Italian | 37 | 1 |
| sv_SE | Swedish | 37 | 1 |
| nl | Dutch | 38 | 1 |
| fr_FR | French (FR) | 45 | 1 |
| fr_CA | French (CA) | 46 | 1 |
| ru | Russian | 93 | 2 |
| da | Danish | 606 | 3 |
| zh | Chinese | 697 | 3 |
| ar | Arabic | 710 | 3 |
| vi | Vietnamese | 712 | 3 |
| hu | Hungarian | 714 | 3 |
| he | Hebrew | 715 | 3 |
| cs | Czech | 717 | 3 |
| sl_SI | Slovenian | 719 | 3 |
| pt_PT | Portuguese (PT) | 719 | 3 |
| ca_ES | Catalan | 721 | 3 |

## Tier Patterns

- **Tier 1** (32–46): Gaps mostly in `web.colonel.*` admin section (23 keys)
- **Tier 2** (93): colonel (51), footer (20), homepage/meta/labels
- **Tier 3** (606–721): Harmonize scaffolding across all sections

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
