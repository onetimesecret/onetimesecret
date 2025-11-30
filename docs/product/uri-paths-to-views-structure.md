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

| URL                                 | File Path                                        |
|-------------------------------------|--------------------------------------------------|
| /                                   | src/apps/secret/conceal/Homepage.vue          |
| /secret/:key                        | src/apps/secret/reveal/ShowSecret.vue     |
| /receipt/:key                       | src/apps/secret/reveal/ShowReceipt.vue    |
| /incoming                           | src/apps/secret/conceal/IncomingForm.vue      |
| /incoming/:key                      | src/apps/secret/conceal/IncomingSuccess.vue   |
| /feedback                           | src/apps/secret/support/Feedback.vue           |
| /signin                             | src/apps/session/views/Login.vue                 |
| /signup                             | src/apps/session/views/Register.vue              |
| /logout                             | src/apps/session/views/Logout.vue                |
| /forgot                             | src/apps/session/views/PasswordResetRequest.vue  |
| /reset-password                     | src/apps/session/views/PasswordReset.vue         |
| /mfa-verify                         | src/apps/session/views/MfaChallenge.vue          |
| /verify-account                     | src/apps/session/views/VerifyAccount.vue         |
| /dashboard                          | src/apps/workspace/dashboard/DashboardIndex.vue  |
| /recent                             | src/apps/workspace/dashboard/DashboardRecent.vue |
| /domains                            | src/apps/workspace/domains/DomainsList.vue       |
| /domains/add                        | src/apps/workspace/domains/DomainAdd.vue         |
| /domains/:extid/verify              | src/apps/workspace/domains/DomainVerify.vue      |
| /domains/:extid/brand               | src/apps/workspace/domains/DomainBrand.vue       |
| /account                            | src/apps/workspace/account/ProfileSettings.vue   |
| /account/settings/security          | src/apps/workspace/account/SecurityOverview.vue  |
| /account/settings/security/password | src/apps/workspace/account/ChangePassword.vue    |
| /account/settings/security/mfa      | src/apps/workspace/account/MfaSettings.vue       |
| /account/settings/api               | src/apps/workspace/account/ApiSettings.vue       |
| /billing/overview                   | src/apps/workspace/billing/BillingOverview.vue   |
| /billing/plans                      | src/apps/workspace/billing/PlanSelector.vue      |
| /billing/invoices                   | src/apps/workspace/billing/InvoiceList.vue       |
| /teams                              | src/apps/workspace/teams/TeamsHub.vue            |
| /teams/:extid                       | src/apps/workspace/teams/TeamView.vue            |
| /teams/:extid/members               | src/apps/workspace/teams/TeamMembers.vue         |
| /colonel                            | src/apps/kernel/views/ColonelIndex.vue           |
| /colonel/users                      | src/apps/kernel/views/ColonelUsers.vue           |
| /colonel/secrets                    | src/apps/kernel/views/ColonelSecrets.vue         |
| /colonel/domains                    | src/apps/kernel/views/ColonelDomains.vue         |
| /colonel/system                     | src/apps/kernel/views/ColonelSystem.vue          |

---
Directory tree:

src/apps/
├── secret/
│   ├── conceal/
│   │   ├── Homepage.vue
│   │   ├── IncomingForm.vue
│   │   └── IncomingSuccess.vue
│   ├── reveal/
│   │   ├── ShowSecret.vue
│   │   └── ShowReceipt.vue
│   ├── support/
│   │   └── Feedback.vue
│   └── router.ts
│
├── session/
│   ├── views/
│   │   ├── Login.vue
│   │   ├── Register.vue
│   │   ├── Logout.vue
│   │   ├── PasswordResetRequest.vue
│   │   ├── PasswordReset.vue
│   │   ├── MfaChallenge.vue
│   │   └── VerifyAccount.vue
│   └── router.ts
│
├── workspace/
│   ├── dashboard/
│   │   ├── DashboardIndex.vue
│   │   └── DashboardRecent.vue
│   ├── domains/
│   │   ├── DomainsList.vue
│   │   ├── DomainAdd.vue
│   │   ├── DomainVerify.vue
│   │   └── DomainBrand.vue
│   ├── account/
│   │   ├── ProfileSettings.vue
│   │   ├── SecurityOverview.vue
│   │   ├── ChangePassword.vue
│   │   ├── MfaSettings.vue
│   │   └── ApiSettings.vue
│   ├── billing/
│   │   ├── BillingOverview.vue
│   │   ├── PlanSelector.vue
│   │   └── InvoiceList.vue
│   ├── teams/
│   │   ├── TeamsHub.vue
│   │   ├── TeamView.vue
│   │   └── TeamMembers.vue
│   └── router.ts
│
└── kernel/
    ├── views/
    │   ├── ColonelIndex.vue
    │   ├── ColonelUsers.vue
    │   ├── ColonelSecrets.vue
    │   ├── ColonelDomains.vue
    │   └── ColonelSystem.vue
    └── router.ts

The key insight: subfolders within each app mirror the domain, not the URL structure. Workspace has dashboard/, domains/, account/, billing/, teams/ because those
are distinct feature areas—even though URLs like /domains sit at root level.


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
│   ├── secret/                    # THE TRANSACTION (Branded, Ephemeral)
│   │   ├── conceal/                 # Input: The Act of Hiding
│   │   │   ├── Homepage.vue         # The main form
│   │   │   └── IncomingRoute.vue    # API-driven concealment
│   │   │
│   │   ├── reveal/                  # Output: The Act of Viewing
│   │   │   ├── Secret.vue           # The secret display (Canonical & Branded)
│   │   │   ├── Burn.vue             # Prematurely destroying the secret
│   │   │   └── ShowReceipt.vue      # The receipt/status (Creator viewing the result)
│   │   │
│   │   └── composables/             # Logic specific to the Secret app
│   │       └── useBranding.ts       # Handles domain_strategy logic
│   │
│   ├── workspace/                   # THE DASHBOARD (Standard, Persistent)
│   │   ├── dashboard/               # Recent secrets, Graphs
│   │   ├── domains/                 # Domain management
│   │   ├── account/                 # User settings
│   │   └── auth/                    # Login/Signup (Entry to Workspace)
│   │
│   └── kernel/                      # THE SYSTEM (Admin)
│       └── ...
│
├── shared/                          # Universal UI & Logic
│   ├── layouts/
│   │   ├── SecretLayout.vue         # Lightweight, brand-aware
│   │   └── WorkspaceLayout.vue      # Sidebar, user menu, heavier
│   └── components/                  # Buttons, Alerts, Forms
```

### 2. Route Mapping

This approach groups routes by what the user is *attempting to do*, not their account status.

| Path | App | Mode | Description |
| :--- | :--- | :--- | :--- |
| `/` | Secret | **Conceal** | User is hiding information. |
| `/incoming` | Secret | **Conceal** | API user is hiding information. |
| `/secret/:id` | Secret | **Reveal** | User is retrieving hidden information. |
| `/receipt/:id` | Secret | **Reveal** | Creator is checking the status of the reveal (Receipt). |
| `/dashboard` | Workspace | **Manage** | User is managing their account/history. |
| `/colonel` | Kernel | **Admin** | User is administering the platform. |

### 3. Why this solves the "Audience" confusion

1.  **The "Recipient" is just a User in Reveal Mode.**
    Whether they are a stranger or a logged-in coworker, if they hit `/secret/xyz`, they enter the **Reveal** flow. The `SecretLayout` loads. If the secret has a custom domain, `useBranding` applies the colors.

2.  **The "Creator" is just a User in Conceal Mode.**
    Whether anonymous or authenticated, if they are on the Homepage, they are in the **Conceal** flow. If they are logged in, the application injects their `custid` into the submission, but the *interaction* (filling out a form) remains the same.

3.  **Shared Logic, Separate Concerns.**
    *   **Conceal** concerns: Form validation, password generation, encryption options.
    *   **Reveal** concerns: Decryption, brute-force protection, burning, feedback.
    *   **Workspace** concerns: Pagination, filtering, billing, team permissions.

This structure allows you to optimize the **Reveal** components for speed and branding (critical for the recipient experience) without worrying about breaking the **Workspace** dashboard (which recipients never see).
