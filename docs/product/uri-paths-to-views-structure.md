---
title: URI Path Mapping
type: reference
status: draft
updated: 2025-11-30
parent: interaction-modes.md
summary: Complete URL to Vue component mapping for the apps architecture
---

# URI Path Mapping

## URI Path → File Path

Here's the URL → File Path mapping:

| URL                                 | File Path                                              |
|-------------------------------------|--------------------------------------------------------|
| /                                   | src/apps/secret/views/Homepage.vue             |
| /secret/:key                        | src/apps/secret/views/reveal/ShowSecret.vue            |
| /receipt/:key                       | src/apps/secret/views/reveal/ShowReceipt.vue           |
| /incoming                           | src/apps/secret/views/conceal/IncomingForm.vue         |
| /incoming/:key                      | src/apps/secret/views/conceal/IncomingSuccess.vue      |
| /feedback                           | src/apps/secret/views/support/Feedback.vue             |
| /signin                             | src/apps/session/views/Login.vue                       |
| /signup                             | src/apps/session/views/Register.vue                    |
| /logout                             | src/apps/session/views/Logout.vue                      |
| /forgot                             | src/apps/session/views/PasswordResetRequest.vue        |
| /reset-password                     | src/apps/session/views/PasswordReset.vue               |
| /mfa-verify                         | src/apps/session/views/MfaChallenge.vue                |
| /verify-account                     | src/apps/session/views/VerifyAccount.vue               |
| /dashboard                          | src/apps/workspace/views/dashboard/DashboardIndex.vue  |
| /recent                             | src/apps/workspace/views/dashboard/DashboardRecent.vue |
| /domains                            | src/apps/workspace/views/domains/DomainsList.vue       |
| /domains/add                        | src/apps/workspace/views/domains/DomainAdd.vue         |
| /domains/:extid/verify              | src/apps/workspace/views/domains/DomainVerify.vue      |
| /domains/:extid/brand               | src/apps/workspace/views/domains/DomainBrand.vue       |
| /account                            | src/apps/workspace/views/account/ProfileSettings.vue   |
| /account/settings/security          | src/apps/workspace/views/account/SecurityOverview.vue  |
| /account/settings/security/password | src/apps/workspace/views/account/ChangePassword.vue    |
| /account/settings/security/mfa      | src/apps/workspace/views/account/MfaSettings.vue       |
| /account/settings/api               | src/apps/workspace/views/account/ApiSettings.vue       |
| /billing/overview                   | src/apps/billing/views/BillingOverview.vue             |
| /billing/plans                      | src/apps/billing/views/PlanSelector.vue                |
| /billing/invoices                   | src/apps/billing/views/InvoiceList.vue                 |
| /teams                              | src/apps/workspace/views/teams/TeamsHub.vue            |
| /teams/:extid                       | src/apps/workspace/views/teams/TeamView.vue            |
| /teams/:extid/members               | src/apps/workspace/views/teams/TeamMembers.vue         |
| /colonel                            | src/apps/colonel/views/ColonelIndex.vue                 |
| /colonel/users                      | src/apps/colonel/views/ColonelUsers.vue                 |
| /colonel/secrets                    | src/apps/colonel/views/ColonelSecrets.vue               |
| /colonel/domains                    | src/apps/colonel/views/ColonelDomains.vue               |
| /colonel/system                     | src/apps/colonel/views/ColonelSystem.vue                |


The key insight: subfolders within each app mirror the domain, not the URL structure. Workspace has dashboard/, domains/, account/, teams/ because those are distinct feature areas—even though URLs like /domains sit at root level. Billing is a separate app due to its distinct business logic and potential for standalone deployment.


## Shared Layout Components

Current layouts (DefaultLayout, ImprovedLayout, ColonelLayout) cut across the new app boundaries.

Question: Do layouts move into apps, or stay shared?

Recommendation: Layouts stay in shared/layouts/ but are named by purpose, not app:
shared/layouts/
├── TransactionalLayout.vue    # Secret (lightweight, brandable)
├── ManagementLayout.vue       # Workspace (sidebar, navigation)
├── AdminLayout.vue            # Kernel (utilitarian)
└── MinimalLayout.vue          # Session (clean, focused)

Each app imports the appropriate layout.


"Conceal" and "Reveal" are excellent terms. They are descriptive, domain-specific, and action-oriented. They clearly delineate the input (hiding data) from the output (showing data), regardless of *who* is doing it.

Here is how the **Interaction Mode** architecture looks using your terminology.

### 1. The Directory Structure

This structure separates the high-traffic, branded "Secret" logic from the authenticated "Workspace" logic.

```text
src/
├── apps/
│   ├── secret/
│   │   ├── views/
│   │   │   ├── conceal/                # Hiding secrets
│   │   │   │   ├── Homepage.vue
│   │   │   │   ├── IncomingForm.vue
│   │   │   │   └── IncomingSuccess.vue
│   │   │   ├── reveal/                 # Viewing secrets
│   │   │   │   ├── ShowSecret.vue
│   │   │   │   ├── ShowReceipt.vue
│   │   │   │   └── AccessDenied.vue    # "External" homepage mode
│   │   │   └── support/                # Feedback
│   │   │       └── Feedback.vue
│   │   ├── components/
│   │   │   ├── conceal/
│   │   │   ├── reveal/
│   │   │   └── support/
│   │   ├── composables/
│   │   │   └── useBranding.ts
│   │   └── router.ts
│   │
│   ├── session/
│   │   ├── views/
│   │   │   ├── Login.vue
│   │   │   ├── Register.vue
│   │   │   ├── Logout.vue
│   │   │   ├── PasswordResetRequest.vue
│   │   │   ├── PasswordReset.vue
│   │   │   ├── MfaChallenge.vue
│   │   │   └── VerifyAccount.vue
│   │   ├── components/
│   │   ├── composables/
│   │   └── router.ts
│   │
│   ├── workspace/
│   │   ├── views/
│   │   │   ├── dashboard/
│   │   │   │   ├── DashboardIndex.vue
│   │   │   │   └── DashboardRecent.vue
│   │   │   ├── domains/
│   │   │   │   ├── DomainsList.vue
│   │   │   │   ├── DomainAdd.vue
│   │   │   │   ├── DomainVerify.vue
│   │   │   │   └── DomainBrand.vue
│   │   │   ├── account/
│   │   │   │   ├── ProfileSettings.vue
│   │   │   │   ├── SecurityOverview.vue
│   │   │   │   ├── ChangePassword.vue
│   │   │   │   ├── MfaSettings.vue
│   │   │   │   └── ApiSettings.vue
│   │   │   └── teams/
│   │   │       ├── TeamsHub.vue
│   │   │       ├── TeamView.vue
│   │   │       └── TeamMembers.vue
│   │   ├── components/
│   │   │   ├── dashboard/
│   │   │   ├── domains/
│   │   │   ├── account/
│   │   │   └── teams/
│   │   ├── composables/
│   │   └── router.ts
│   │
│   ├── billing/                       # THE COMMERCE (Subscription Management)
│   │   ├── views/
│   │   │   ├── BillingOverview.vue
│   │   │   ├── PlanSelector.vue
│   │   │   └── InvoiceList.vue
│   │   ├── components/
│   │   ├── composables/
│   │   └── router.ts
│   │
│   └── colonel/
│       ├── views/
│       │   ├── ColonelIndex.vue
│       │   ├── ColonelUsers.vue
│       │   ├── ColonelSecrets.vue
│       │   ├── ColonelDomains.vue
│       │   └── ColonelSystem.vue
│       ├── components/
│       ├── composables/
│       └── router.ts
│
└── shared/
    ├── layouts/
    │   ├── TransactionalLayout.vue  # Secret (lightweight, brandable)
    │   ├── ManagementLayout.vue     # Workspace (sidebar, navigation)
    │   ├── AdminLayout.vue          # Kernel (utilitarian)
    │   └── MinimalLayout.vue        # Session (clean, focused)
    ├── components/
    └── composables/
```

### 2. Router Architecture

> **Note**: Each app contains a `router.ts` file. After the initial migration, these are **placeholder stubs** — routes remain in `src/router/*.routes.ts` until route consolidation is completed. The migration script moves views and rewrites imports but does not migrate route definitions.

### 3. Route Mapping

This approach groups routes by what the user is *attempting to do*, not their account status.

| Path | App | Mode | Description |
| :--- | :--- | :--- | :--- |
| `/` | Secret | **Conceal** | User is hiding information. |
| `/incoming` | Secret | **Conceal** | API user is hiding information. |
| `/secret/:key` | Secret | **Reveal** | User is retrieving hidden information. |
| `/receipt/:key` | Secret | **Reveal** | Creator is checking the status of the reveal (Receipt). |
| `/dashboard` | Workspace | **Manage** | User is managing their account/history. |
| `/colonel` | Kernel | **Admin** | User is administering the platform. |

### 3. Why this solves the "Audience" confusion

1.  **The "Recipient" is just a User in Reveal Mode.**
    Whether they are a stranger or a logged-in coworker, if they hit `/secret/xyz`, they enter the **Reveal** flow. The `TransactionalLayout` loads. If the secret has a custom domain, `useBranding` applies the colors.

2.  **The "Creator" is just a User in Conceal Mode.**
    Whether anonymous or authenticated, if they are on the Homepage, they are in the **Conceal** flow. If they are logged in, the application injects their `custid` into the submission, but the *interaction* (filling out a form) remains the same.

3.  **Shared Logic, Separate Concerns.**
    *   **Conceal** concerns: Form validation, password generation, encryption options.
    *   **Reveal** concerns: Decryption, brute-force protection, burning, feedback.
    *   **Workspace** concerns: Pagination, filtering, billing, team permissions.

This structure allows you to optimize the **Reveal** components for speed and branding (critical for the recipient experience) without worrying about breaking the **Workspace** dashboard (which recipients never see).
