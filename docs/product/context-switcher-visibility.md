---
title: Context Switcher Visibility
type: reference
status: current
updated: 2026-07-04
---

# Context Switcher Visibility

How the organization and domain context switchers — and the user-menu identity
chip — adapt to a user's role, plan, and workspace shape. The aim is a clean
surface for a brand-new self-signup user, with progressive disclosure as they
add domains, collaborators, or organizations.

Implemented in:

- `src/shared/composables/useScopeSwitcherVisibility.ts` — org switcher gating
- `src/apps/workspace/components/navigation/DomainContextSwitcher.vue` — domain CTA
- `src/apps/workspace/components/navigation/OrganizationContextBar.vue` — static fallback
- `src/shared/components/navigation/UserMenu.vue` — identity chip

## Domain context dropdown — Add vs. Manage

The call-to-action depends on whether the user can manage domains (owner or
admin of the active organization) and how many custom domains already exist.

| User state | Affordance |
|------------|-----------|
| Owner/admin, 0 custom domains | Prominent **"Add domain"** link in the dropdown footer |
| Owner/admin, ≥1 custom domain | Compact **`[+]` icon** in the dropdown header + **"Manage Domains"** footer link |
| Member (cannot manage domains) | Neither affordance |

Rationale: "Manage Domains" is meaningless with nothing to manage, so a
zero-domain owner is steered straight to adding one. Once a domain exists, the
add action demotes to an icon — the user has already learned the flow, and an
admin's job is administering rather than adding.

## Organization context dropdown — hidden for solo users

The org switcher is **hidden** for a brand-new self-signup user and reappears
once there is something to switch between or administer. It shows only when all
of these hold (`showOrgSwitcher`):

- Not on a custom domain (there the domain *is* the org scope)
- The route allows it (`scopesAvailable.organization !== 'hide'`)
- The org-switcher feature is enabled
- The user **can manage orgs** (`canManageOrgs`):
  - billing disabled → owner role is sufficient
  - billing enabled → owner **and** the `manage_orgs` entitlement
- The context is **not a trivial solo default** (`isSoloDefaultContext`): the
  user has exactly one organization (their auto-created "Default Workspace") and
  is its only member

When the switcher is hidden because the context is solo, the static org-name
chip in the context bar is suppressed too — nothing about the lone default
workspace is surfaced.

## User-menu identity chip

The chip beside the domain in the user-menu header follows the **same** solo /
`manage_orgs` logic, so it appears and disappears in step with the org switcher.

| Context | Chip |
|---------|------|
| Non-solo org context (multi-member or multi-org) | **Role badge** — `Owner` / `Admin` |
| Solo default, billing enabled, no `manage_orgs` | **`Free`** chip, links to `/billing` |
| Solo default, billing enabled, has `manage_orgs` | Role badge |
| Solo default, billing **disabled** | **Hidden** — matches the hidden org switcher |

Rationale: an "Owner" badge is noise for a lone free user. On a billing install
it becomes a subtle plan indicator and upsell; on a standalone install — where
there is no plan tier or billing page — it simply disappears, so the chip only
ever shows alongside the org context dropdown.

## Related

- [Membership Entitlements](../authorizations/membership-entitlements.md)
- [Organization Invites](organization-invites.md)
