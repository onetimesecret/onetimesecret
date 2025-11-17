# Translation Audit Report
**Date:** 2025-11-17
**Branch:** `i18n/quality-review-20151116-1`
**Total Locales Checked:** 29
**Total JSON Files per Locale:** 17

## Executive Summary

A comprehensive audit was performed on all locale translations to identify keys with English content that still need translation. Keys with underscore (`_`) prefixes are intentionally left in English and were excluded from this report.

**Total Missing Translations: 4,740 across 27 locales**

## Locales by Priority

### Critical (>500 missing translations)
| Locale | Missing | Percentage | Notes |
|--------|---------|------------|-------|
| da (Danish) | 1,403 | 29.6% | Requires significant translation work |
| ru (Russian) | 633 | 13.4% | Major gaps in translation |
| nl (Dutch) | 566 | 11.9% | Substantial missing content |

### High Priority (100-500 missing)
| Locale | Missing | Percentage |
|--------|---------|------------|
| zh (Chinese) | 406 | 8.6% |
| pt_BR (Portuguese - Brazil) | 265 | 5.6% |
| it_IT (Italian) | 197 | 4.2% |
| da_DK (Danish - Denmark) | 142 | 3.0% |
| de (German) | 120 | 2.5% |
| fr_FR (French - France) | 104 | 2.2% |

### Medium Priority (50-100 missing)
| Locale | Missing | Percentage |
|--------|---------|------------|
| fr_CA (French - Canada) | 91 | 1.9% |
| pl (Polish) | 86 | 1.8% |
| pt_PT (Portuguese - Portugal) | 86 | 1.8% |
| ko (Korean) | 75 | 1.6% |
| ja (Japanese) | 73 | 1.5% |
| de_AT (German - Austria) | 70 | 1.5% |
| es (Spanish) | 67 | 1.4% |
| mi_NZ (Māori - New Zealand) | 67 | 1.4% |
| bg (Bulgarian) | 56 | 1.2% |
| uk (Ukrainian) | 54 | 1.1% |

### Low Priority (10-50 missing)
| Locale | Missing | Percentage |
|--------|---------|------------|
| tr (Turkish) | 46 | 1.0% |
| sv_SE (Swedish) | 44 | 0.9% |
| el_GR (Greek) | 41 | 0.9% |
| sl_SI (Slovenian) | 27 | 0.6% |

### Minimal Issues (<10 missing)
| Locale | Missing | Percentage |
|--------|---------|------------|
| ca_ES (Catalan) | 8 | 0.2% |
| hu (Hungarian) | 5 | 0.1% |
| vi (Vietnamese) | 5 | 0.1% |
| cs (Czech) | 3 | 0.1% |

## Common Patterns

### Most Affected Files Across Locales:
1. **_common.json** - Core UI strings, many locales have gaps
2. **uncategorized.json** - Legacy/uncategorized strings
3. **auth-advanced.json** - Security metadata and OWASP references
4. **feature-*.json** - Feature-specific strings

### Frequently Missing Keys:
- Security documentation metadata (auth-advanced.json)
- Template strings with placeholders (e.g., "{0}/{1}/{2}")
- Brand names and proper nouns (intentionally left English in some cases)
- Recent additions from harmonization work

## Recommendations

### Immediate Actions:
1. **Danish (da)** - This locale has 1,403 missing translations and needs urgent attention
2. **Russian (ru)** - 633 missing translations, high user base likely
3. **Dutch (nl)** - 566 missing translations

### Translation Workflow:
1. Review the detailed report: `translation-audit-report.txt`
2. Prioritize by locale based on user base and strategic importance
3. Focus on high-impact files first (_common.json, auth.json, feature-secrets.json)
4. Consider automation for template strings that are purely formatting

### Special Considerations:
- **Template strings** (e.g., `{0}/{1}`) may be intentional and locale-neutral
- **Brand names** (e.g., "Onetime Secret", "Google") typically stay in English
- **Technical terms** may have acceptable English usage in some locales
- **Security metadata** under `_meta` keys are documentation for translators and may not need translation

## Key Insights

### Most Problematic Files:
1. **uncategorized.json** - 2,017 missing translations (88 avg/locale)
2. **_common.json** - 643 missing translations across ALL 27 locales (24 avg/locale)
3. **auth-advanced.json** - 515 missing translations (primarily security metadata)
4. **account.json** - 312 missing translations
5. **account-billing.json** - 193 missing translations

### Commonly Missing Keys (22/27 locales):
These are excellent candidates for batch translation:
- `web.UNITS.ttl.duration` - "{count} {unit}"
- `web.UNITS.ttl.noOptionsAvailable` - "---"
- Template strings with formatting placeholders
- Brand names (may be intentional): "Onetime Secret", "Google", "Microsoft Edge"
- Icons/emojis: ❌, ✅

### Special Cases:
Many of the widely-missing keys fall into these categories:
- **Pure formatting templates** (e.g., `{0}/{1}/{2}`) - May not need translation
- **Brand names** - Usually stay in English
- **Security metadata** in auth-advanced.json - Documentation for translators
- **Proper nouns** - Names, products, etc.

## Files Generated:
- **translation-audit-report.txt** - Full detailed report (15,048 lines)
- **TRANSLATION-AUDIT-SUMMARY.md** - This executive summary
- **audit-translations.js** - Audit script for future runs
- **analyze-by-file.js** - Analysis script for file-level statistics
- **analyze-common-missing.js** - Script to find commonly missing keys

## How to Use These Tools:

### Re-run the audit:
```bash
node audit-translations.js > translation-audit-report.txt
```

### Analyze by file:
```bash
node analyze-by-file.js
```

### Find batch translation opportunities:
```bash
node analyze-common-missing.js
```

## Next Steps:
1. **Review false positives** - Some keys may be intentionally English (brands, technical terms)
2. **Prioritize Danish (da)** - 1,403 missing translations is critical
3. **Batch translate common keys** - 22 keys are missing in 22+ locales
4. **Focus on _common.json** - Affects all locales, high-impact file
5. **Engage translation teams** - Use the per-locale reports to create specific work packages
6. **Re-run audit** - Verify completion after translation work
7. **Consider automation** - Template strings and formatting may be scriptable
