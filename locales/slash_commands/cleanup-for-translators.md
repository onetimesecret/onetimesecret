---
description: Sync for-translators.md content back to glossary.md and language-notes.md source files
argument-hint: <locale-path> (e.g., src/content/docs/de/translations)
allowed-tools: Read, Edit, Glob, Grep
disallowed-tools: Skill(self:write-slash-command), Skill(d:write-slash-command)
---

# Cleanup For-Translators Guide

Review the for-translators.md file and compare it against glossary.md and language-notes.md in the specified directory. The for-translators guide is a generated document combining content from those two source files plus links to universal resources. If there is any content in for-translators.md that does not exist in either glossary.md or language-notes.md, update the appropriate source file to include that content.

## Target Directory

$ARGUMENTS

If no argument provided, prompt for the locale path (e.g., `src/content/docs/de/translations`).

## Content Classification Guidelines

### Content for glossary.md

- Terminology tables (multi-column with translations across regional variants)
- UI element translations
- Status term translations
- Time-related term translations
- Security feature terminology
- Account-related term translations
- Domain-related term translations
- Error message translations
- Button and action translations
- Marketing term translations
- Multi-language comparison tables (preserve column structure)

### Content for language-notes.md

- Language-specific translation rules and rationale
- Formality choices (e.g., du/Sie for German, tu/vous for French)
- Regional variation guidance within this specific locale
- Voice usage rules (active vs. passive, imperative vs. declarative)
- Critical translation rules with examples
- Key translation decision documentation (why certain choices were made)
- Number/date formatting conventions
- Implementation guidelines for translators
- Testing recommendations for formality choices

### Content NOT to sync (universal resources)

The following sections in for-translators.md are links to universal content in `/en/translations/universal/` and should NOT be synced to locale files:

- "Universal Translation Resources" section (links only)
- Content about translating "secret" → lives in universal/secret-concept.md
- Content about password vs passphrase → lives in universal/password-passphrase.md
- Voice and tone patterns → lives in universal/voice-and-tone.md
- Brand terms guidance → lives in universal/brand-terms.md

## Important Rules

1. **Do not modify for-translators.md** - it is a generated output file
2. **Preserve multi-column tables** in glossary.md when they exist (regional variants like DE vs AT, or FR vs CA)
3. **language-notes.md is locale-specific** - content should be specific to this one locale only (e.g., `de` covers German Germany conventions, while `de_AT` has its own separate file)
4. **Add section headings** in language-notes.md if needed for clarity
5. **Maintain existing document structure** - add content to appropriate existing sections when possible
6. **Skip universal content** - do not sync content that belongs in /en/translations/universal/

## Workflow

1. Read all three files: for-translators.md, glossary.md, language-notes.md
2. Identify sections/content in for-translators.md
3. Skip the "Universal Translation Resources" section (these are links, not content)
4. Check if each remaining section exists in one of the source files
5. For missing content, classify it per the guidelines above
6. Update the appropriate source file with the missing content
7. Report what was added and to which file

## Regenerating After Sync

After syncing content to source files, regenerate the for-translators.md:

```bash
./bin/generate-for-translators <locale>
# or for all locales:
pnpm generate:for-translators
```
