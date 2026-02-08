# Brand Customization System — Product Bible

Version: 1.5 | Status: Living Document | Owner: Product/Engineering
PRD Reference: PR #2483 — Centralize brand customization system
Last Audit: 2026-02-08

## Overview

The brand customization system enables Onetime Secret installations and custom domains
to express a complete visual identity through configuration alone — no code changes, no
rebuilds. A single hex color generates an 11-shade oklch palette (44 CSS vars across 4
palette variants) at runtime. Product name, typography, corner style, and support contact
flow through i18n and CSS variables.

The system's north star: **Onetime Secret's own design (`#dc4a22`, Zilla Slab, the 秘
logo) should be expressible purely as a configuration of this system.** If we can eat our
own dogfood, every self-hosted operator and custom-domain customer gets the same level of
polish.

This document set is organized in five parts, each in its own file for focused reading
and independent editing.

---

## Table of Contents

### [Part 1: Context](brand-part1-context.md)

The problem, personas, current state, and gaps.

- 1.1 [Problem Statement](brand-part1-context.md#11-problem-statement)
- 1.2 [User Personas](brand-part1-context.md#12-user-personas)
- 1.3 [Current State](brand-part1-context.md#13-current-state)
- 1.4 [Dogfood Readiness Assessment](brand-part1-context.md#14-dogfood-readiness-assessment)
- 1.5 [Gap Analysis: Ring Model](brand-part1-context.md#15-gap-analysis-ring-model)

### [Part 2: Architecture](brand-part2-architecture.md)

The solution: resolution layers, design tokens, dual-lifecycle model.

- 2.1 [Core Architecture](brand-part2-architecture.md#21-core-architecture)
- 2.2 [Design Token Architecture](brand-part2-architecture.md#22-design-token-architecture)
- 2.3 [Dual-Lifecycle Model](brand-part2-architecture.md#23-dual-lifecycle-model)

### [Part 3: Cross-Cutting Concerns](brand-part3-cross-cutting-concerns.md)

Accessibility, security, and quality assurance.

- 3.1 [Accessibility & Contrast](brand-part3-cross-cutting-concerns.md#31-accessibility--contrast)
- 3.2 [Security Considerations](brand-part3-cross-cutting-concerns.md#32-security-considerations)
- 3.3 [Quality Assurance: Linting & Visual Regression](brand-part3-cross-cutting-concerns.md#33-quality-assurance-linting--visual-regression)

### [Part 4: Implementation Specifics](brand-part4-implementation.md)

Email branding and operator documentation.

- 4.1 [Email Branding](brand-part4-implementation.md#41-email-branding)
- 4.2 [Operator Documentation](brand-part4-implementation.md#42-operator-documentation)

### [Part 5: Meta-Content](brand-part5-meta.md)

Open questions, decision log, document maintenance, and change history.

- 5.1 [Open Questions](brand-part5-meta.md#51-open-questions)
- 5.2 [Decision Log](brand-part5-meta.md#52-decision-log)
- 5.3 [Document Management Notes](brand-part5-meta.md#53-document-management-notes)
- 5.4 [Change History](brand-part5-meta.md#54-change-history)

---

## References

- PR #2483: [Centralize brand customization system](https://github.com/onetimesecret/onetimesecret/pull/2483)
- Branch: `feature/brand-customization-system` (19 commits)
- Serena memory: `branding-centralization-architecture`
- Design system guide: `style.css` @theme block
- Email templates: `lib/onetime/mail/views/`
- Tailwind v4 capabilities reference: `docs/product/tailwind-v4-capabilities.md`
