---
title: Organization / Workspace Terminology
type: reference
status: current
updated: 2026-07-04
---

# Organization / Workspace Terminology

The product calls the same entity **"Workspace"** in some UI copy and
**"Organization"** in other UI copy, API responses, and code (`Organization`
type, `useOrganizationStore`, `web.organizations.*` i18n keys, `/org/:extid`
routes). This is intentional, not drift: the rename is being rolled out
**display-text only**, and only where progressive disclosure calls for it.

Nothing in code changes — identifiers, routes, store names, and i18n key IDs
stay `organization`/`org` throughout. Only the rendered `text` value in the
locale content files (`locales/content/en/*.json`) changes per surface below.

## Rationale: progressive disclosure

> Limit exposure of the "organization" concept on the onboarding experience
> and, to a greater extent, the free-plan user's experience.

A brand-new or solo free user has one auto-created "Default Workspace" and no
reason to think in terms of a multi-tenant "organization" — that word implies
team administration they haven't opted into yet. "Workspace" reads as *your
place to work*; "Organization" reads as *a legal/administrative entity you
manage*. The further a surface sits from onboarding — real team management,
billing administration, API/backend errors — the more acceptable "Organization"
becomes, since by that point the user has opted into the concept it names.

This mirrors the same progressive-disclosure principle already documented in
[Context Switcher Visibility](context-switcher-visibility.md): both the org
switcher's visibility *and* its label follow "don't show a solo/free user
machinery they don't need yet."

## Renamed to "Workspace" (done)

| Surface | File(s) | Notes |
|---|---|---|
| Org context dropdown | `OrganizationScopeSwitcher.vue` + `workspace-organizations.json` | Header, "Manage Workspaces", "Select a workspace", locked/fallback text |
| `/orgs` list page | `OrganizationsSettings.vue` | H1, empty-state copy, tab title |
| Create-organization modal | `CreateOrganizationModal.vue` | Title now reuses the `create_workspace` key; description/label/error retexted |
| Billing zero-org empty state | `BillingOverview.vue` | "No Workspaces" heading + reuses `create_workspace` for the CTA. Not reachable today (every account gets a default org on signup) — fixed for consistency/future-proofing |

## Still "Organization" — onboarding-adjacent, not yet renamed

| Surface | Key | Why it's still open |
|---|---|---|
| Org settings → General tab field label | `web.organizations.display_name` = "Organization Name" | A solo/free user *can* reach `/org/:extid`; this label is the one remaining "organization" word on that page (tabs read Domains/Members/SSO/Settings; the H1 is the workspace's own name). Left as-is pending explicit scope confirmation — it's shared with the settings form only, low risk to rename next. |

## Intentionally left as "Organization" — deeper / admin surfaces

These only appear once a user has opted into multi-member or paid
administration — past the point progressive disclosure is protecting:

- **Org settings page**: `general_settings` ("General Settings"),
  `entitlements_title` ("Organization Entitlements")
- **Danger zone**: `delete_organization`, `delete_organization_warning`,
  `leave_organization*`, `default_org_delete_notice_*`
- **Members**: `members.title`/`members.description` (`MembersTable.vue`),
  role descriptions ("...organization settings", "...organization
  resources"), removal/leave confirmation strings
- **Gear icon** in the context dropdown: `organization_settings` used only
  as its aria-label ("Organization Settings") — kept to match the
  destination page it links to

## Intentionally left as "Organization" — API / backend-facing

Not renamed because they're consumed by API clients and/or matched by
tests, not just displayed:

- `api.invite.errors.organization_no_longer_exists`, `...already a member of
  this organization`
- `api-entitlements-errors.json`: "Unable to verify entitlements
  (organization context unavailable)", "Organization management requires a
  plan upgrade"
- `api-incoming-errors.json`: "Custom domain organization could not be
  resolved"
- `secret-manage.errors.no_organization_context`

## Orphaned — zero user exposure, not rendered anywhere

Found during the audit but not referenced by any `.vue` template; safe to
batch-clean later without user-facing effect: `about_title`,
`about_description`, `getting_started_title`, `getting_started_description`,
`single_user_info_title`, `single_user_info_description`,
`organizations_description`, `organization_plural`, `new_organization`, the
long-form `page_description`, `organization_information`,
`organization_settings_description`, and `invitations.title` ("Organization
Invitations" — the members page itself doesn't render this heading).

## Related

- [Context Switcher Visibility](context-switcher-visibility.md)
- [Organization Invites](organization-invites.md)
