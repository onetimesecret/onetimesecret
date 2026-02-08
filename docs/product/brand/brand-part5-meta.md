> Part of the [Brand Customization System](brand-customization-system.md) product bible.

# Part 5: Meta-Content

---

## 5.1 Open Questions

## 5.2 Decision Log

Decisions made during the brand system development. For significant architectural
decisions, create a formal ADR in `docs/architecture/decision-records/`.

| #   | Date    | Decision                                                   | Rationale                                                                                                         | ADR |
| --- | ------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --- |
| D1  | 2026-01 | Use oklch color space for palette generation               | Perceptually uniform, handles gamut clipping, modern browser support                                              | —   |
| D2  | 2026-01 | Generate 4 palettes from 1 hex (brand, comp, dim, dimcomp) | Covers light/dark and accent needs without additional config                                                      | —   |
| D3  | 2026-01 | Zod `.nullish()` not `.default()` for brand schema         | Schema validates format only; the store resolves defaults. This preserves the 3-layer fallback chain.             | —   |
| D4  | 2026-01 | Remove `extend.colors` from `tailwind.config.ts`           | Tailwind v4 uses CSS-only `@theme`. Config colors were a v3 holdover causing dual-source confusion.               | —   |
| D5  | 2026-01 | Replace `useBrandI18n` composable with standard `t()`      | Standard i18n with explicit `{ product_name }` parameter is simpler and more consistent than a custom composable. | —   |
| D6  | 2026-02 | Rename config key from `branding:` to `brand:`             | Shorter, consistent with other config section naming (site:, redis:, etc.)                                        | —   |
| D7  | 2026-02 | Keep in-house token pipeline; do not adopt TokiForge       | No oklch support, no Tailwind v4, will continue with `brand-palette.ts`.                                          | —   |

We will move this content to a single, focus ADR file once the system is stable and the major decisions are finalized. For now, this log captures the evolving decision landscape during development.

---

## 5.3 Document Management Notes

### Why Markdown (and Its Limits)

This document set captures the full picture across multiple files. Markdown works well for:

- Version control alongside code (git diff, PR review)
- Searchability (grep, IDE search)
- Portability (renders on GitHub, in editors, as HTML)

Where it falls short:

- **No interactive tables** — The comparison matrix would benefit from sortable columns
  and filtering. Consider exporting to a spreadsheet for stakeholder presentations.
- **No visual diffing** — When brand palettes change, a visual comparison tool (e.g.,
  Figma, Storybook) would show the actual color difference better than hex codes.
- **No living metrics** — Success metrics (adoption counts, hardcoded-value counts) go
  stale. Consider a script that counts `brand-*` class usage vs hardcoded colors and
  outputs a freshness report.

### Suggested Complementary Tools

| Tool                                              | Purpose                                                                        | When to Use                          |
| ------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------ |
| **Penpot**                                        | Shared design spec with W3C DTCG tokens synced to `--color-brand-*` vars       | Design ↔ code sync                   |
| ~~TokiForge~~ (evaluated, not adopted — see [D7](#52-decision-log))   | Was considered for semantic alias remapping; in-house pipeline is more capable | —                                    |
| GitHub Issues                                     | Task tracking for brand system work items                                      | Ongoing                              |
| Storybook                                         | Visual component library with brand variants                                   | When component coverage warrants it  |
| ADR files (`docs/architecture/decision-records/`) | Record key decisions from Open Questions                                       | As questions are resolved            |
| `brand-audit.sh` script                           | Automated count of hardcoded values                                            | Run before each release              |
| Stylelint                                         | Enforce token naming conventions, catch hardcoded hex values (see [Section 3.3](brand-part3-cross-cutting-concerns.md#33-quality-assurance-linting--visual-regression)) | On commit / in CI                    |
| Playwright visual regression                      | Screenshot baselines across brand color variants (see [Section 3.3](brand-part3-cross-cutting-concerns.md#33-quality-assurance-linting--visual-regression))             | On PRs touching brand pipeline files |

### CI/CD Pipeline for Brand Integrity

The `brand-audit.sh` script is a starting point. A full CI gate for brand system integrity
follows this pipeline pattern:

1. **Lint CSS on commit** — Stylelint catches hardcoded colors and naming violations
2. **Visual regression against brand configurations** — Playwright screenshots under
   3–4 representative colors, compared against baselines
3. **Token schema validation** — Verify that `brand-palette.ts` output matches the
   expected 44-variable schema (11 shades × 4 palettes)
4. **Block deployment on failure** — Any of the above failing prevents merge

This runs alongside existing checks (`pnpm run lint`, `pnpm run type-check`,
`pnpm run test:all:clean`). The brand-specific steps add coverage for the CSS variable
pipeline that TypeScript and unit tests do not reach.

### Keeping This Document Set Fresh

1. **After competitive research**: Update [Section 1.5](brand-part1-context.md#15-gap-analysis-ring-model) with new findings.
2. **After resolving an Open Question**: Move it to [Section 5.2](#52-decision-log) (Decision Log) with the
   resolution.
3. **Quarterly**: Re-run the automated audit (grep for hardcoded values) and update
   [Section 1.4](brand-part1-context.md#14-dogfood-readiness-assessment) counts.

---

## 5.4 Change History

| Version | Date       | Author              | Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------- | ---------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1.0     | 2026-02-08 | Product/Engineering | Initial document from 4-agent dogfood audit                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 1.1     | 2026-02-08 | Product/Engineering | Added security section (11), operator docs (13). Fixed palette count, font_family gap, open question ownership. Fresh-eyes review feedback.                                                                                                                                                                                                                                                                                                                                    |
| 1.2     | 2026-02-08 | Product/Engineering | Added 7 planned features: login page customization, per-domain theme extension, semantic color aliases, dark theme auto-generation, per-org branding, custom email sender, font file upload. Reframed custom CSS as Tailwind v4 theme extension. Expanded Sections 5, 6, 7, 8, 9, 11, 12, 14.                                                                                                                                                                                  |
| 1.3     | 2026-02-08 | Product/Engineering | Fact-check pass against Tailwind v4 capabilities reference. Corrected "100% CSS" claim to scope it to theme definitions (Section 3). Fixed `branddimcomp-*` palette prefix to `brandcompdim-*` (Section 7). Added design token tooling subsection (Section 7). Added Section 11: CSS linting (Stylelint) and visual regression testing (Playwright, Lost Pixel). Expanded Section 15 with CI/CD pipeline pattern for brand integrity. Renumbered sections sequentially (1–17). |
| 1.4     | 2026-02-08 | Product/Engineering | Restructured into five-part layout: Context, Architecture, Cross-Cutting Concerns, Implementation Specifics, Meta-Content. Nested Design Token Architecture and Dual-Lifecycle Model under Architecture. Added Decision Log cross-references (D1–D6). No content rewritten.                                                                                                                                                                                                    |
| 1.5     | 2026-02-08 | Product/Engineering | Split into 5 part files with hub index. Cross-references converted to relative markdown links. No content rewritten.                                                                                                                                                                                                                                                                                                                                                           |

---
