---
title: Legal & Policy Link Configuration
type: plan
status: draft
updated: 2026-08-22
---

## Problem

Terms and privacy links in signup flows and branded secret reveal footers
are hardcoded to removed `/info/terms` and `/info/privacy` routes.
Meanwhile, the only way to configure these URLs today is inside the
generic `footer_links` group structure, which is not convenient for
first-class legal links and is not reused by the affected components.

## Goal

Promote common legal/policy URLs to explicit, top-level config settings so
they can be configured once and used consistently across the app.

## Proposed config settings

Add explicit environment variables and config schema fields:

| Setting                   | Env var        | Typical use                        |
| -------------------------- | -------------- | ----------------------------------- |
| Terms of Service           | `TERMS_URL`    | Signup agreement, branded reveal footer |
| Privacy Policy             | `PRIVACY_URL`  | Signup agreement, branded reveal footer |
| Data Processing Agreement  | `DPA_URL`      | Enterprise/legal footer link        |
| Cookie Policy              | `COOKIE_URL`   | Cookie banner / footer              |
| Acceptable Use Policy      | `AUP_URL`      | Abuse/legal footer link             |
| Security                   | `SECURITY_URL` | Security page / footer              |

## Backend work

- [ ] Add `site.legal.terms_url`, `privacy_url`, `dpa_url`, `cookie_url`,
      `aup_url`, `security_url` (or similar) to
      `etc/defaults/config.defaults.yaml`.
- [ ] Expose the values in the bootstrap payload under a new `ui.legal`
      (or `site.legal`) object.
- [ ] Update Zod schemas in `src/schemas/contracts/bootstrap.ts` and
      config shapes.
- [ ] Keep `footer_links` as the consumer, but allow it to reference these
      values or default to them.

## Frontend work

- [ ] Add a typed `legalUrls` getter/composable in `bootstrapStore` or a
      shared helper.
- [ ] Update `SignUpForm.vue` to use configurable `termsUrl` and
      `privacyUrl` instead of `/info/terms` and `/info/privacy`.
- [ ] Update `InviteSignUpForm.vue` similarly.
- [ ] Update `SecretFooterAttribution.vue` to use configurable URLs when
      `showTerms=true`.
- [ ] Hide each link when its URL is not configured.
- [ ] Use `<a>` for external URLs and `<router-link>` only for relative
      internal paths.

## Cleanup

- [ ] Remove `/info/privacy` from `e2e/all/brand-customization.spec.ts`
      `publicPaths`.
- [ ] Add/update tests for the new bootstrap schema fields and component
      behavior.

## Acceptance criteria

- [ ] `TERMS_URL`, `PRIVACY_URL`, `DPA_URL`, `COOKIE_URL`, `AUP_URL`,
      `SECURITY_URL` are documented in defaults and read from env.
- [ ] Signup forms and branded reveal footer use the configured URLs.
- [ ] Links are hidden when no URL is configured.
- [ ] No hardcoded `/info/terms` or `/info/privacy` references remain in
      the affected components.
- [ ] Tests pass.
