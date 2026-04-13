---
title: Übersetzungsanleitung für österreichisches Deutsch (de_AT)
description: Overlay on de.md — only what differs for the Austrian German locale
---

TODO: revert the json files to ce852a5e8 (2025-11-15).


# Translation Guidance for Austrian German (de_AT)

This is an **overlay** on `de.md`. Inherit everything from `de.md` unless explicitly overridden here. Glossary, terminology, and the object/content split for `secret` (`Geheimnis` vs `Nachricht`) all live in `de.md` and apply identically to `de_AT`. This file documents only the Austrian-specific overrides.

## Address Form (hard lock)

**Always `Sie` / `Ihr` / `Ihnen`. Never `du` / `dein` / `dich` / `dir`.**

Applies to every user-facing string in `locales/content/de_AT/`: UI labels, buttons, errors, status messages, email subject lines and bodies, marketing copy, help text, tooltips. No exceptions.

**Rationale:** Onetime Secret in the Austrian market is positioned as a B2B security product. Austrian business communication expects formal address in any commercial or institutional context. Informal `du` reads as either consumer-grade or unprofessionally familiar — both wrong for the brand. The Germany locale (`de.json`) makes a different choice for tech-sector reasons (see `de.md` § 4); that choice does not transfer to Austria.

**If you find `du`-form in an existing `de_AT` file, it is a bug.** Two harmonization passes in early April 2026 (`4982d4f84`, `b08e59838`) propagated `du`-form across the locale under the label "harmonization". Fix occurrences when you encounter them; do not match them.

**Examples:**

| Wrong (du-form) | Correct (Sie-form) |
|-----------------|--------------------|
| Gib deine Anmeldedaten ein | Geben Sie Ihre Anmeldedaten ein |
| Möchtest du dieses Geheimnis verbrennen? | Möchten Sie dieses Geheimnis verbrennen? |
| Brauchst du Hilfe? | Benötigen Sie Unterstützung? |
| Bitte versuche es erneut | Bitte versuchen Sie es erneut |
| Melde dich bei deinem Konto an | Melden Sie sich bei Ihrem Konto an |
| Deine sichere Nachricht ist bereit | Ihre sichere Nachricht ist bereit |

## Glossary

Inherit from `de.md`. The "German (AT)" column in the glossary tables there is authoritative for AT-specific terminology (`Sicherheitsphrase`, `verbrennen`, `Eintragen`, `benutzerdefinierter Bereich`, `Huch`, etc.). Do not duplicate it here. If a term needs to change, change it in `de.md` so the table stays single-source.

## Placeholder values

Where the English source has placeholder data and the choice is open, prefer Austrian-flavored values:

| Field | de_AT |
|-------|-------|
| Example email address | `kontakt@musterfirma.gv.at` |
| Domain TLDs in copy and screenshots | `.at` over `.de` |

## Austrian flavor — scope

**In scope:** Formal `Sie` register, AT-specific terminology already pinned in the `de.md` glossary, Austrian placeholder data.

**Out of scope:** Viennese colloquialisms (`Jänner`, `Feber`, `heuer`, `Stiege`). These are dialect markers that read as informal or confusing in business contexts. Use neutral DACH business German except where the glossary explicitly pins an AT-specific term.

If a string is correct in `de.md` and the only Austrian variant would be a colloquialism, stay with the `de.md` term. Austrian flavor is not the goal in itself; Austrian register and the small set of pinned terminology choices are.

## Reference baseline

The authoritative snapshot for tone and term usage in `de_AT` is:

```
f95b03f44:src/locales/de_AT.json   (2025-04-15)
```

This is the last hand-curated state of the locale before the 2026 harmonization passes that introduced `du`-form regression. When in doubt about phrasing for an existing key, check what the baseline used:

```bash
git show f95b03f44:src/locales/de_AT.json | grep -B1 -A1 'key_name'
```

The baseline uses the pre-reorg flat-file structure. Keys may need remapping to the current per-file layout under `locales/content/de_AT/`.

## Anti-patterns documented from the 2026 regression

1. **Register flip under "harmonization".** Two commits (`4982d4f84`, `b08e59838`) replaced formal `Sie` with informal `du` across all 20 `de_AT` files. Harmonization is a key-structure operation; it does not change `text` field values. If a "harmonization" PR touches translation text, it is mislabeled.
2. **Global `Geheimnis` → `Nachricht` substitution.** Erased the object/content split documented in `de.md` § 1. Both terms are correct in their own contexts; neither is a blanket replacement for the other.
3. **Austrian placeholder data overwritten with US placeholders.** `kontakt@musterfirma.gv.at` was replaced with `tom@myspace.com`, removing one of the few markers that the locale was actually localized for Austria.
4. **Brand vocabulary left untranslated mid-sentence.** `Powered by` was left as raw English instead of `Bereitgestellt von`. If a phrase is not on the brand-terms allowlist, translate it.

## Mechanical guardrail (recommended)

Prose guidance — including this file — gets skimmed under time pressure. The only check that survives the next harmonization pass regardless of who or what runs it is a CI lint:

- Grep `locales/content/de_AT/**.json` value strings for `\b(du|dein|deine[mnrs]?|dich|dir)\b`
- Fail the build with a list of offending file:key pairs
- Maintain a tiny allowlist file for the rare cases where informal is genuinely correct (e.g., a quoted customer testimonial)

This belongs in CI before any further translation passes are run against the locale.
