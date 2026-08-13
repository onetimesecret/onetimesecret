---
id: "011"
status: accepted
title: "ADR-011: I18n Initialization in Test Setup"
---

## Status

Accepted

## Date

2026-05-24

## Context

Production initializes I18n via a `SetupI18n` step in `boot!`. Unit tests skip `boot!`, so production code paths that call `I18n.t` (added in PR #3033) raise `I18n::InvalidLocale` in specs that don't manually configure I18n.

The prior pattern — opt-in I18n setup in individual spec files or shared contexts — produced silent failures when new code paths reached `I18n.t` without their callers knowing to opt in. PR #2892 fixed 28 silent skips traceable to this pattern.

## Decision

**Initialize I18n globally in `spec_helper.rb`. Do not stub `I18n.t`.**

A `before(:each)` block ensures `I18n.available_locales` includes `:en` and `I18n.default_locale = :en` before every example. Specs that need richer locale data may layer it; the baseline guarantees `I18n.t` does not raise.

Logic that needs to test "this error happened" stores a symbol (`error_key: :blank`) and resolves to a string at the presentation layer — the `ActiveModel::Errors` pattern. Tests assert against the symbol; the resolver is tested separately.

Mature Ruby OSS converges on this: Rails, Discourse, GitLab, Mastodon, and Devise all initialize I18n globally in `spec_helper`/`rails_helper`, none gate it behind opt-in contexts, and none stub `I18n.t`. Rails defaults `enforce_available_locales` to `true` and frames disabling it as back-compat. Since OTS is not a Rails app, the manual setup in `spec_helper` is the equivalent of what `i18n_railtie` does automatically in those projects.

## Trade-offs

- **We lose**: A pure-Ruby unit test that calls `I18n.t` is no longer fully isolated from I18n state. The before-each hook touches a global.
- **We gain**: New code paths that call `I18n.t` work in every spec without retrofitting. No silent skips when I18n setup is forgotten.
- **Risk**: The baseline (`[:en]` only) won't catch missing translations in other locales — that belongs to the locale-file checker, not unit specs.
