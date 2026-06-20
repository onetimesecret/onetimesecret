---
id: "014"
status: proposed
title: "ADR-014: Pass-through i18n in Vitest Component Tests"
---

## Status

Proposed

## Date

2026-06-20

## Context

Vue component tests using `createI18n` with partial message definitions produce inconsistent behavior: defined keys translate, undefined keys return raw keys. Assertions must know which keys are defined, and adding translations breaks unrelated tests.

ADR-011 solved the Ruby analog (global I18n init in `spec_helper.rb`). This addresses the frontend.

## Decision

**Use pass-through i18n in all Vitest component tests: keys render as-is, no translations.**

```typescript
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  missingWarn: false,
  fallbackWarn: false,
  missing: (_, key) => key,
  messages: { en: {} },
});
```

Assertions check raw keys: `expect(wrapper.text()).toContain('web.domains.title')`. Tests verify the correct key is wired to the correct DOM location — translation content is validated by CI locale checks, not component tests.

Tests that specifically verify locale switching or pluralization may define targeted messages; these are rare.

## Consequences

Component tests verify locales keys are wired up correctly, not the translation content. Updating translations doesn't require updating test assertions. One pattern across all component tests.
