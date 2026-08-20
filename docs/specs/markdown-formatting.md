# Markdown Formatting

Status: proposed.

## Rule

Exclude Markdown from Prettier formatting; use markdownlint-cli2 to lint.

## Why

Prettier reprints the whole file from an AST. Two of its Markdown decisions
are hardcoded with no option to disable:

- emphasis normalized to `_underscore_` (we write `*asterisk*`)
- table columns padded to a common width

Both rewrite lines the author did not touch, so a one-line docs edit lands as
a 150-line diff. `markdownlint-cli2` is rule-based: `--fix` touches only lines
that violate an enabled rule, and every rule is toggleable — including
emphasis style (MD049/MD050) and line length (MD013, off; our prose is
hand-wrapped).

Config knobs that _are_ available in `.prettierrc` (`singleQuote`,
`embeddedLanguageFormatting`) cover only the frontmatter quoting and fenced
code blocks — not the two rewrites above. Hence exclusion rather than tuning.

## Wiring

- `.prettierignore` — `*.md`, so `pnpm format` and editor Prettier skip it.
- `.zed/settings.json` — `"Markdown": { "format_on_save": "off" }`. Zed's
  default Markdown formatter is bundled Prettier and reads our `.prettierrc`;
  without this, saving a doc reformats it. `.vscode/settings.json` scopes its
  formatters per language and needs no change.
- `.markdownlint-cli2.jsonc` — rule config, globs `docs/**/*.md` and `*.md`.
- `pnpm lint:md`, plus a pre-commit hook.

Lint runs at commit, not at save. Doc fixes belong in their own commit, not
mixed into an unrelated change.

## Not in scope

Prose style (terminology, voice, product-name spelling) is a different job —
Vale, if we take it on. `markdownlint` checks structure only.
