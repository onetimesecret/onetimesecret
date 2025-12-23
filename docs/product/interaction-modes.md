---
title: Interaction Modes
type: technical-design
status: draft
version: "1.0"
updated: 2025-11-30
summary: Frontend architectural model organizing code by user intent (Conceal/Reveal/Manage/Admin) rather than audience or domain
---

# Interaction Modes

> [!NOTE]
> **We are trying to create our "Pit of Success": a way of organizing files and folders that makes it hard to put code in the wrong place.**

This document defines the architectural model for the frontend. It answers:
- Where does this code belong?
- Why does this view look different in different contexts?
- How do the pieces compose?

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [The Three Dimensions](#the-three-dimensions)
4. [Solution: Organize by Interaction Mode](#the-solution-organize-by-interaction-mode)
5. [Architecture](#architecture)
6. [Technical Design](#modes--dimensions)
7. [Implementation Examples](#more-on-the-homepage)
8. [Decision Log](#decision-log)
9. [Appendix: Clarifications FAQ](#appendix-clarifications-faq)
10. [Related Documents](#related-documents)

---

## Executive Summary

**Core insight**: Organize frontend code by *what the user is doing* (Interaction Mode), not by *who they are* (audience) or *how it looks* (domain branding).

| App | Mode | Purpose |
|-----|------|---------|
| Secret | Conceal/Reveal | Transactional (create & view secrets) |
| Workspace | Manage | Account management |
| Colonel | Admin | System administration |
| Session | Gateway | Authentication |

Three independent dimensions control rendering:
- **Interaction Mode** (design-time): Which app handles the request
- **Domain Context** (runtime): How it looks (canonical vs branded)
- **Homepage Mode** (deployment-time): Whether creation is permitted

---

## Problem Statement

**Current Problem**: Views are organized by domain (`canonical/`, `branded/`) not by audience.

This creates:
- **Duplication**: Two components doing the same thing with different styling
- **Unclear ownership**: Which audience does `canonical/ShowSecret.vue` serve?
- **Fragile boundaries**: Changes to reveal logic must be synchronized across folders
- **Innovation friction**: Fear of breaking the "other" variant discourages iteration

## The Three Dimensions

We have three inputs that determine how a view renders. Conflating them was the source of our architectural confusion.

### Dimension 1: Interaction Mode (Design-Time)

Interaction Mode is a structural decision made when the route is defined. It determines which app handles the request.

| Route         | App       | Mode    | Designed For                               |
|---------------|-----------|---------|--------------------------------------------|
| /             | Secret    | Conceal | Creator (anon or auth) submitting the form |
| /secret/:key  | Secret    | Reveal  | Recipient viewing shared content           |
| /receipt/:key | Secret    | Reveal  | Creator checking delivery status           |
| /dashboard/*  | Workspace | Manage  | Account holder managing history            |
| /colonel/*    | Colonel    | Admin   | System administrator                       |
| /signin       | Session   | Gateway | Identity verification                      |

### Dimension 2: Domain Context (Runtime)

Domain Context is detected per-request by `Rack::DetectHost` + `DomainStrategy` middleware. It determines presentation, not structure.

| Domain Type | Detection                     | Affects                               |
|-------------|-------------------------------|---------------------------------------|
| Canonical   | Config-defined, static        | Default branding, full marketing copy |
| Custom      | Per-request header inspection | Custom branding, minimal chrome       |

Each custom domain carries its branding configuration and belongs to exactly one organization. Recognizing the domain implicitly identifies both.

#### Domain Scope (Workspace Extension)

Within the Workspace app, Domain Context can be elevated from a presentation wrapper to a **persistent scope**. This applies to users who manage multiple custom domains (e.g., consultants serving multiple organizations).

| Concept | Role | Applies To |
|---------|------|------------|
| Domain Context | Presentation wrapper (runtime) | Secret app |
| Domain Scope | Management filter + defaults (session) | Workspace app |

When Domain Scope is active:
- Privacy defaults (TTL, passphrase requirements) are scoped to the selected domain
- Secrets created from the dashboard use the scoped domain automatically
- The scope persists across navigation within the session

Users with no custom domains operate in canonical context implicitly (no scope selector shown).

### Dimension 3: Homepage Mode (Deployment-Time)

Homepage Mode is a scoped gatekeeper configured at deployment. It only applies to the Conceal context (Homepage).

| Mode     | Who Can Create       | Who Can View | Homepage Shows        |
|----------|----------------------|--------------|-----------------------|
| Open     | Anyone               | Anyone       | Form + explainer      |
| Internal | Internal IPs/headers | Anyone       | Form + explainer      |
| External | Nobody               | Anyone       | "Nothing to see here" |

### The Insight

Each dimension answers a different question at a different time:

| Dimension        | Binding Time    | Question                    | Role                          |
|------------------|-----------------|-----------------------------| ------------------------------|
| Interaction Mode | Design-time     | "What is the user doing?"   | Router — selects the App      |
| Domain Context   | Runtime         | "How should it look?"       | Wrapper — adapts presentation |
| Domain Scope     | Session         | "Which domain am I managing?"| Filter — scopes Workspace     |
| Homepage Mode    | Deployment-time | "Is creation permitted?"    | Gatekeeper — gates access     |

These are independent axes. Homepage Mode gates; Domain Context wraps:

```
Request to /
      │
      ▼
┌─────────────────────┐
│  Homepage Mode      │ ◄── GATE (Open? Internal? External?)
│  (Deployment-time)  │
└─────────────────────┘
      │
      ├─ External ──────► AccessDenied.vue (stop here)
      │
      ▼ Open/Internal
┌─────────────────────┐
│  Domain Context     │ ◄── WRAPPER (Canonical? Custom?)
│  (Runtime)          │
└─────────────────────┘
      │
      ▼
┌─────────────────────┐
│  Homepage.vue       │ ◄── Unified component, adapts to context
└─────────────────────┘
```

The complete dimensional matrix for Conceal:

```
                          HOMEPAGE MODE (deployment-time)
                          ┌──────────┬──────────┬──────────┐
                          │  Open    │ Internal │ External │
┌─────────────────────────┼──────────┴──────────┼──────────┤
│ DOMAIN      │ Canonical │    Form + copy      │ Disabled │
│ CONTEXT     ├───────────┼─────────────────────┼──────────┤
│ (runtime)   │ Custom    │    Form + brand     │ Branded  │
│             │           │                     │ Disabled │
└─────────────┴───────────┴─────────────────────┴──────────┘
```

For Reveal, only two dimensions apply (Homepage Mode is irrelevant):

```
              ┌─────────────────────────────────────┐
              │         DOMAIN CONTEXT              │
              │    (runtime, per-request)           │
              ├─────────────────┬───────────────────┤
              │   Canonical     │     Custom        │
┌─────────────┼─────────────────┼───────────────────┤
│ Reveal      │ Standard reveal │ Branded reveal    │
└─────────────┴─────────────────┴───────────────────┘
```

For Workspace/Colonel, Homepage Mode does not apply:

```
┌─────────────┬─────────────────────────────────────┐
│ Manage      │ Domain Context applies (plan-gated) │
├─────────────┼─────────────────────────────────────┤
│ Admin       │ Always OTS-branded (no custom)      │
└─────────────┴─────────────────────────────────────┘
```

### Current Problem

Views are organized by Domain Context (a presentation axis):

```
src/views/secrets/
├── canonical/    ← Domain-based folder
│   └── ShowSecret.vue
└── branded/      ← Domain-based folder
    └── ShowSecret.vue
```

This creates:
- **Duplication**: Two components doing the same thing with different styling
- **Unclear ownership**: Which audience does `canonical/ShowSecret.vue` serve?
- **Fragile boundaries**: Changes to reveal logic must be synchronized across folders
- **Innovation friction**: Fear of breaking the "other" variant discourages iteration

### The Solution: Organize by Interaction Mode

The new architecture organizes by what the user is doing, with Domain Context and Homepage Mode handled via composables:

```
src/apps/
├── secret/           ← Interaction Mode: Transaction
│   ├── conceal/      ← Sub-mode: Input (Homepage Mode applies here)
│   │   ├── Homepage.vue
│   │   └── AccessDenied.vue
│   └── reveal/       ← Sub-mode: Output (Domain Context applies here)
│       └── ShowSecret.vue
├── workspace/        ← Interaction Mode: Management (no dimensions apply)
├── session/          ← Interaction Mode: Gateway
└── colonel/           ← Interaction Mode: Administration
```

Safe passage is handled by composables that compute `uiConfig` from all applicable dimensions:

```javascript
// Conceal context: Gate first, then wrap
const homepageMode = useHomepageMode();      // Dimension 3: Gatekeeper
const { isCanonical } = useBranding();       // Dimension 2: Wrapper

if (homepageMode.isDisabled) return <AccessDenied />;
return isCanonical ? <CanonicalLayout /> : <BrandedLayout />;

// Reveal context: Only wrap (no gate)
const { theme, uiPermissions } = useSecretContext();  // Dimension 2 + actor role
```



## Architecture

### Current Request FLow


```text
  ┌──────────────────────────────────────────────────────────────────────┐
  │                         REQUEST FLOW                                 │
  ├──────────────────────────────────────────────────────────────────────┤
  │  HTTP Request                                                        │
  │       ↓                                                              │
  │  Rack::DetectHost (extract domain from headers)                      │
  │       ↓                                                              │
  │  DomainStrategy (classify: canonical | subdomain | custom | invalid) │
  │       ↓                                                              │
  │  window.__ONETIME_STATE__.domain_strategy                            │
  │       ↓                                                              │
  │  Container Components (HomepageContainer, ShowSecretContainer)       │
  │       ↓                                                              │
  │  ┌────────────────┐    OR    ┌────────────────┐                      │
  │  │  canonical/    │          │  branded/      │                      │
  │  │  ShowSecret    │          │  ShowSecret    │                      │
  │  │  UnknownSecret │          │  UnknownSecret │                      │
  │  └────────────────┘          └────────────────┘                      │
  └──────────────────────────────────────────────────────────────────────┘
```


### Proposed

1.  **The Apps (Level 1 - Structural):**
    *   **Secret:** The public/branded transactional layer.
    *   **Workspace:** The authenticated management layer.
    *   **Colonel:** The system administration layer.
    *   **Session:** The authentication gateway.

2.  **The Logic (Level 2 - Behavioral):**
    *   **Secret Context:** A dimensional matrix handling the high variance of user states (Owner/Recipient/Anon) unique to secret transactions.
    *   **RBAC:** A permission system used in Workspace/Colonel to gate specific features based on plan/role.


```bash
src/
├── apps/                            # DISTINCT INTERACTION MODES
│   ├── secret/                      # THE TRANSACTION (Branded/Canonical)
│   │   ├── views/
│   │   │   ├── conceal/             # Homepage, Incoming API
│   │   │   ├── reveal/              # ShowSecret, ShowReceipt, Burn
│   │   │   └── support/             # Feedback
│   │   └── router.ts                # Routes: /, /secret/*, /receipt/*
│   │
│   ├── workspace/                   # THE MANAGEMENT (Standard UI)
│   │   ├── dashboard/               # Recent secrets, activity
│   │   ├── domains/                 # Custom domain management
│   │   ├── account/                 # Profile, security settings
│   │   ├── teams/                   # Team management
│   │   └── router.ts                # Routes: /dashboard, /account, /domains, /teams
│   │
│   ├── billing/                     # THE COMMERCE (Subscription Management)
│   │   ├── views/                   # Overview, plans, invoices
│   │   └── router.ts                # Routes: /billing/*
│   │
│   ├── colonel/                      # THE SYSTEM (Admin)
│   │   ├── views/                   # Colonel views
│   │   └── router.ts                # Routes: /colonel/*
│   │
│   └── session/                     # THE GATEWAY (Authentication)
│       ├── views/
│       │   ├── Login.vue
│       │   ├── Register.vue
│       │   ├── PasswordReset.vue
│       │   ├── MfaChallenge.vue
│       │   └── Logout.vue
│       ├── router.ts                # Routes: /signin, /signup, /logout, /mfa-verify
│       └── logic/
│           └── traffic-controller.ts
│
├── shared/
│   ├── branding/                    # Logic for White-labeling (only used by 'secret')
│   │   └── useBrandContext.ts       # The composable replacing our Container logic
│   └── components/                  # Buttons, Inputs, Layouts
```



### Apps - By Interaction Modes

A new mental model to get used to. Not public<->private or recipient<->creator. A "Recipient" is just a user in Secret Mode. We're not separating "Public" vs "Private"; separating "The Secret Lifecycle" from "Account Management."

#### 1. The Secret (Transactional)
*   **Intent:** Single-task focus. I want to *conceal* something, or I want to *reveal* something.
*   **Timeframe:** Ephemeral. Users get in, do the thing, and get out.
*   **Audience:**
    *   **The Creator:** (Anon or Auth) submitting the form on the homepage.
    *   **The Recipient:** (Stranger or Coworker) viewing the secret.
*   **Key Characteristic:** This is the **only** part of the app that needs Branding/White-labeling. It must be lightweight and high-performance.

#### 2. The Workspace (Management)
*   **Intent:** Administration and Organization. I want to manage my historical data, my team, or my billing.
*   **Timeframe:** Persistent. Users browse, review, and configure.
*   **Audience:** Account Holders (Creators).
*   **Key Characteristic:** Always authenticated. Always Onetimesecret-branded (Recipients never see this). Complex UI state.
*   **Domain Scope:** Users managing multiple custom domains can select a scope, filtering the management view and applying domain-specific defaults to new secrets.

#### 3. The Colonel (System)
*   **Intent:** Platform Oversight.
*   **Audience:** Admins (Colonel).
*   **Key Characteristic:** Utilitarian, dangerous, raw data views.

#### 4. Session (the gateway/access hole)

Auth as a standalone module, responsible for Identity & Access. It doesn't care about secrets or dashboards; it cares about credentials and tokens. Auth pages require a layout that is neither the "Marketing" layout (too noisy) nor the "Dashboard" layout (requires auth).


##### Integration with Other Modes

* From Secret (Public): The "Sign In" button in the header is just a link to apps/session.
* From Workspace (Private): When a token expires, the interceptor redirects to apps/session with a ?return_to= query param.
* From Colonel (Admin): Uses the same apps/session but might require higher assurance (e.g., immediate MFA prompt).


## Modes & Dimensions

Interaction Modes are our source of truth for architecture; the dimensional matrix is our source of truth for Secret mode behavior.

We have successfully decoupled the **Static Structure** (Files/Routes) from the **Dynamic Behavior** (State/Logic).

This model aligns perfectly with **Domain-Driven Design (DDD)** principles:
1.  **Interaction Modes** = **Bounded Contexts** (The Architecture).
2.  **Dimensional Matrix** = **Domain Logic** (The Rules within the Context).

Here is how to concretely apply this "Level 2" logic so it doesn't leak into the "Level 1" structure.

### 1. The Matrix Implementation (The "Brain")

We shouldn't just return raw booleans (`isOwner`, `isAuthenticated`). That forces our Views to do the math (`v-if="isOwner && !isAuthenticated"`).

Instead, our `useSecretContext` should distill the matrix into a **finite state** or **UI Definition**.

**File:** `apps/secret/composables/useSecretContext.ts`

```typescript
import { computed } from 'vue';
import { useAuthStore } from '@/shared/stores/auth';
import { useRoute } from 'vue-router';

export function useSecretContext() {
  const auth = useAuthStore();
  const route = useRoute();

  // --- Dimensions (The Raw Inputs) ---
  const isAuthenticated = computed(() => auth.isAuthenticated);

  // "Is the viewer the person who created this specific secret?"
  const isOwner = computed(() => {
      return auth.user?.id === route.params.creatorId; // Simplified logic
  });

  // --- The Matrix Resolution (The Output) ---

  // Determine the "Actor" role for this specific transaction
  const actorRole = computed(() => {
    if (isOwner.value) return 'CREATOR';
    if (isAuthenticated.value) return 'RECIPIENT_AUTH';
    return 'RECIPIENT_ANON';
  });

  // Determine UI Behavior based on the Matrix
  const uiConfig = computed(() => {
    switch (actorRole.value) {
      case 'CREATOR':
        return {
          showBurnControl: true,
          showCapabilitiesUpgrade: false,
          headerAction: 'DASHBOARD_LINK'
        };
      case 'RECIPIENT_AUTH':
        return {
          showBurnControl: false,
          showCapabilitiesUpgrade: false, // Already has an account
          headerAction: 'DASHBOARD_LINK'
        };
      case 'RECIPIENT_ANON':
      default:
        return {
          showBurnControl: false,
          showCapabilitiesUpgrade: true,  // Suggest an account
          headerAction: 'SIGNUP_CTA'
        };
    }
  });

  return { actorRole, uiConfig };
}
```

### 2. The View Implementation (The "Body")

Now, our component (in Level 1) is dumb. It asks the Matrix (Level 2) what to do. It doesn't calculate logic.

**File:** `apps/secret/reveal/ShowSecret.vue`

```vue
<template>
  <div class="secret-layout">
    <SecretDisplay :content="secret" />

    <!-- The View doesn't ask "Is this an owner?", it asks "Do I show the burn control?" -->
    <BurnButton v-if="uiConfig.showBurnControl" />

    <UpgradeFooter v-if="uiConfig.showCapabilitiesUpgrade" />
  </div>
</template>

<script setup>
import { useSecretContext } from '../composables/useSecretContext';

// The Context drives the behavior
const { uiConfig } = useSecretContext();
</script>
```

### 3. Why Workspace Doesn't Need This

As you noted, **Workspace** (Dashboard) is homogenous.
*   **Auth:** Always True.
*   **Role:** Always "User".
*   **Context:** Always Management.

The only variation in Workspace is **Permissions** (e.g., "Can I delete this domain?"). This is not a *Dimensional Matrix*; it is standard **RBAC** (Role-Based Access Control).

*   **Secret Matrix:** "Who are you relative to *this specific URL/Secret*?" (Highly Dynamic)
*   **Workspace RBAC:** "What is our static permission level?" (Highly Stable)

### Final Architecture Summary

We can now document our architecture with absolute clarity:

1.  **The Apps (Level 1 - Structural):**
    *   **Secret:** The public/branded transactional layer.
    *   **Workspace:** The authenticated management layer.
    *   **Colonel:** The system administration layer.
    *   **Session:** The authentication gateway.

2.  **The Logic (Level 2 - Behavioral):**
    *   **Secret Context:** A dimensional matrix handling the high variance of user states (Owner/Recipient/Anon) unique to secret transactions.
    *   **RBAC:** A permission system used in Workspace/Colonel to gate specific features based on plan/role.

This creates a **"Pit of Success"**: It is hard to put code in the wrong place because the boundaries are defined by *what the code does*, not just *who looks at it*.

## Appendix: Clarifications FAQ

### 1. Branding: Split Data from Presentation

Important distinction: **brand data** vs **brand presentation**.

The Workspace needs to know about branding to configure it and preview it. The Secret app needs to know about branding to render it live.


| Concern | Who Needs It | Location |
|---------|--------------|----------|
| Brand types, API calls, data fetching | Secret (to render), Workspace (to manage) | `shared/api/brand.ts`, `shared/types/brand.ts` |
| Brand presentation logic (colors, corners, instructions) | Secret only | `apps/secret/branding/` |

Workspace imports brand *data* to populate forms. It doesn't import the presentation logic because Workspace is always OTS-branded. The boundary stays clean. BUT, there can be Workspace specific presentation components to "mock-up"/preview the data "how it will look".

* shared/branding/ (The Tools)
  * What: Types, Utility functions (e.g., calculateContrastColor), and the BrandPreviewComponent.
  * Why: Workspace imports this to show the Creator what they are building. Secret app imports this to render the final result.
* apps/secret/branding/ (The Context)
  * What: useBrandContext.ts, BrandEnforcer.ts.
  * Why: This is the logic that reads the window.location, determines if a brand applies to the current route, and injects CSS variables into the :root. The Workspace never does this (it only previews inside a box), so this logic stays in Secret.

```
shared/
├── branding/        # fetchBrandConfig(), saveBrandConfig()
│
apps/
├── secret/
│   └── branding/
│       ├── useBrandPresentation.ts   # Applies brand to UI
│       ├── BrandLogo.vue             # Renders brand logo
│       └── BrandStyles.ts            # CSS variable injection
└── workspace/
    └── views/domains/
        └── DashboardDomainBrand.vue  # Imports shared/api/brand, not secret/branding
```

### 2. Session as an "App" vs. "Service"

View the Session module as an internal Identity Provider (IdP).

Think of apps/session as the airport security checkpoint. It is a distinct physical space. You enter from the street (Public), pass through Security (Session), and emerge into the terminal (Workspace). You cannot check in your bags while standing in the metal detector.

### 3. What About Feedback?

Feedback belongs in apps/secret. The Secret app is the Transactional Public Interface.

* The Transaction: A user (anonymous or known) wants to send a message to the platform.
* The Context: It is ephemeral. The user fills it out and leaves.
* The Branding: If I am on acme.onetimesecret.com/secret/123 and I click "Report this Secret" or "Feedback", I expect to stay within the "Acme" visual context. I should not be jarred back to the Canonical generic theme just to fill out a form.


### 4. How Do Routers Compose?

Explicit Import (Centralized) is the correct approach.

While "self-registration" sounds decoupled, it introduces non-determinism in route matching order. In Vue Router, order matters (first match wins). You need strict control to ensure specific routes (like /secret/:id) are checked before wildcards or 404s.

**Keep the distinct route files, but aggregate them in the main router index.**

```ts
// src/router/index.ts
import { createRouter, createWebHistory } from 'vue-router';

// Import modules
import { routes as sessionRoutes } from '@/apps/session/routes';
import { routes as workspaceRoutes } from '@/apps/workspace/routes';
import { routes as colonelRoutes } from '@/apps/colonel/routes';
import { routes as secretRoutes } from '@/apps/secret/routes'; // Includes 404 wildcard

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    // 1. Session (Gateway) - Check first (e.g., /logout, /login)
    ...sessionRoutes,

    // 2. Colonel (Admin) - High specificity
    ...colonelRoutes,

    // 3. Workspace (Dashboard) - Auth required
    ...workspaceRoutes,

    // 4. Secret (Public/Transactional) - Contains catch-all 404
    // Must be last because it likely handles dynamic params like /:id
    ...secretRoutes,
  ],
});

// Global Navigation Guards
router.beforeEach((to, from, next) => {
    // Basic global logic (e.g., NProgress start)
    next();
});
```
`

### 5a. The Receipt View - What mode?

`/receipt/:receiptIdentifier` belongs in Secret. Although it requires "ownership," it is still an Interaction Mode of "Transaction/Lifecycle," not "Management." The ownership is historically based on having/knowing the unguessable URL -- not authentication state. There can still be a "Receipt View equivalent" in Workspace mode: an in-page workflow where the act of creating a secret doesn't take you to a subsequent page.


### 5b. Code Implication: Shared Business Components

* The "Receipt View" is the **Receipt** of a transaction. It belongs in **Secret**.
* The "Dashboard View" is the **Ledger** of transactions. It belongs in **Workspace**.

Since both apps deal with the same data structure (a Secret/Receipt), but wrap it in different workflows, you need strict component composition. This separation ensures that when you improve the "Dashboard," you don't accidentally break the "Receipt" that an anonymous user is looking at:


The architecture now clearly separates the two ways a secret is created, driven by the **Interaction Mode**.

| Feature | Secret App (The Lifecycle) | Workspace App (The Tool) |
| :--- | :--- | :--- |
| **Trigger** | Homepage Form | "Create Secret" Modal/Inline |
| **Action** | Full Page POST + Redirect | AJAX POST + State Update |
| **Outcome** | Redirects to `/receipt/:key` (The Receipt View) | Stays on Dashboard; shows Toast/Modal |
| **Context** | "I am handing this off." | "I am managing my data." |
| **Ownership** | Bearer Token (URL) | Database Record (Account ID) |


### 6. Where do Homepage files live?

The Homepage is the conceal interface, not a marketing funnel. It does have marketing content though but more for explaining what it is ("Keep sensitive info out of your chat logs and email") and onboarding/redirecting Interaction Modes.

We have another dimension that's deployment-time (not runtime):

| Homepage Mode   | Who Can Create       | Who Can View | Homepage Shows        |
|-----------------|----------------------|--------------|-----------------------|
| Open            | Anyone               | Anyone       | Form + explainer      |
| Internal        | Internal IPs/headers | Anyone       | Form + explainer      |
| External        | Nobody               | Anyone       | "Nothing to see here" |

This is orthogonal to the branded/canonical dimension:

              ┌─────────────────────────────────────────────┐
              │             HOMEPAGE MODE                    │
              │    (config-time, per-instance)              │
              ├─────────────┬─────────────┬─────────────────┤
              │   Open      │  Internal   │    External     │
┌─────────────┼─────────────┼─────────────┼─────────────────┤
│ Canonical   │ Form+copy   │ Form+copy   │ Disabled msg    │
├─────────────┼─────────────┼─────────────┼─────────────────┤
│ Branded     │ Form+brand  │ Form+brand  │ Brand+disabled  │
└─────────────┴─────────────┴─────────────┴─────────────────┘

So the structure holds:

```
apps/secret/
├── views/
│   ├── Homepage.vue          # The form + explainer (respects homepage mode)
│   ├── conceal/
│   │   ├── IncomingForm.vue  # API-consumer conceal
│   │   └── IncomingSuccess.vue
│   ├── reveal/
│   │   ├── ShowSecret.vue
│   │   ├── ShowReceipt.vue
│   │   └── AccessDenied.vue  # "External" mode / disabled state
│   └── support/
│       └── Feedback.vue
└── router.ts
```

The useSecretContext() composable gains a homepage mode input:

```ts
  // From window.__ONETIME_STATE__ or config
  const homepageMode = computed(() =>
    WindowService.get('homepage_mode') // 'open' | 'internal' | 'external'
  );

  const canCreateSecrets = computed(() =>
    homepageMode.value !== 'external'
  );

  And the Homepage router guard checks this before even rendering:

  // apps/secret/router.ts
  {
    path: '/',
    component: () => import('./views/Homepage.vue'),
    beforeEnter: (to) => {
      const mode = WindowService.get('homepage_mode');
      if (mode === 'external') {
        return { name: 'AccessDenied' };
      }
    }
  }
```

```yaml
# Homepage Mode
#
# Determines which homepage experience to show based on the request
# headers. It can change the content presented to a visitor when they
# navigate to the homepage but it does not expand or restrict access.
#
# ✓ Can do: Hide the Create Secret form for external users
# ✗ Cannot do: Grant access to endpoints for creating secret links
#
# This does not protect API endpoints and has no effect on existing
# authentication or authorization logic.
#
# Detection Methods (evaluated in order):
#   1. matching_cidrs - Client IP must match one of these subnets
#   2. mode_header - Fallback if no CIDR match (requires header value = mode)
#
homepage:
  mode: <%= ENV['UI_HOMEPAGE_MODE'] || nil %>
  matching_cidrs: <%= ENV['UI_HOMEPAGE_MATCHING_CIDRS']&.split(',')&.map(&:strip) || [] %>
  mode_header: <%= ENV['UI_HOMEPAGE_MODE_HEADER'] || 'O-Homepage-Mode' %>
  trusted_proxy_depth: <%= ENV['UI_HOMEPAGE_TRUSTED_PROXY_DEPTH']&.to_i || 1 %>
  trusted_ip_header: <%= ENV['UI_HOMEPAGE_TRUSTED_IP_HEADER'] || 'X-Forwarded-For' %>
```

### 7. Incoming Secrets

A destination page with a variation of the secret create form that the user submits and the secret link is sent automatically to an email address associated to the page (e.g. so top-level /incoming is a project-wide configuration). Authenticated user can generate an incoming secrets page (e.g. /incoming/abcd1234). But can a non-authenticated user create an incoming secrets page? I don't know.

An "Incoming Page" is a persistent resource that requires an owner. It needs a verified destination (email) and a configuration state. Anonymous users cannot "own" persistent resources in this system.


**Why it fits the Matrix (Secret) and not Workspace:**

* Branding: If a user created a branded secret, the "Receipt" page should likely reflect that brand (or at least not clash with it). Workspace never supports custom branding.
* Access Pattern: Users often arrive here via a direct link saved immediately after conceal, not by browsing a table in a dashboard.
* _The "Single Item" Rule_:
  * Secret app is for viewing singular entities in high fidelity (The Secret, The Receipt).
  * Workspace is for viewing collections (List of secrets, list of domains).


### 8. Secret State

Question: The matrix handles CREATOR | RECIPIENT_AUTH | RECIPIENT_ANON, but the secret lifecycle has more states. Should useSecretContext() also ingest secret state, or should that be a separate composable (useSecretLifecycle())?

Answer: Separate them.

Mixing "Environmental Context" (Branding/Audience) with "Entity State" (Secret Lifecycle) violates Single Responsibility Principle and creates testing nightmares.

useSecretContext() answers: "Where are we?" (Domain) and "Who is looking?" (Identity).
useSecretLifecycle() answers: "What is the status of this specific data?"

You should model the Secret Lifecycle as a Finite State Machine (FSM).



## Decision Log

### Why This Architecture Was Chosen

We were struggling because we were attempting to map Personas (Who they are) to code, which is fluid. A recipient can indeed be a creator, an admin, or a total stranger. Instead of organizing by Identity, we organize by Interaction Mode (What they are doing).

### Example: The Coworker Scenario

> A recipient could be a coworker of the creator.

Under the old model:
- Route thinks: "This is the recipient view, show public/branded layout"
- But user is authenticated with premium account
- Mismatch: they see a stripped-down experience despite having capabilities

Under the Interaction Modes model:
- **Auth state**: Authenticated
- **Content relationship**: Recipient (they have the secret link)
- **Capabilities**: single_team (they have their own account)
- **Intent**: Retrieve a secret

The UI can now make nuanced decisions:
- Show the branded secret reveal (content relationship = recipient)
- But include "Create our own" CTA (capabilities = premium)
- Use authenticated header (auth state = authenticated)
- Skip marketing copy (intent = retrieve, not discover)


## More on the Homepage

Handling the Homepage Mode Matrix
You have two orthogonal inputs controlling this view. Do not try to solve this with CSS or minor v-if tweaks. Solve it with Component Composition.

The Logic Flow
Homepage Mode acts as a Gatekeeper (Do we show the form?).
Branding Mode acts as a Wrapper (How do we decorate the form?).
Implementation: The Orchestrator (Homepage.vue)
This file is responsible for intersecting the two dimensions.




```vue
<!-- apps/secret/conceal/Homepage.vue -->
<template>
  <!-- Gating Layer: Homepage Mode -->
  <AccessDenied v-if="homepageMode.isDisabled" />

  <component :is="layoutComponent" v-else>
    <!-- The Shared Core: Passed into the slot of the layout -->
    <CreateSecretForm
      :allowed-options="homepageMode.options"
    />
  </component>
</template>

<script setup>
import { computed } from 'vue';
import { useHomepageMode } from '@/shared/composables/useHomepageMode';
import { useBranding } from '@/apps/secret/composables/useBranding';

// Components
import CanonicalLayout from './layouts/CanonicalHome.vue';
import BrandedLayout from './layouts/BrandedHome.vue';
import AccessDenied from './views/AccessDenied.vue';

// 1. Check Homepage Mode (Open vs External)
const homepageMode = useHomepageMode();

// 2. Check Branding (Canonical vs Custom)
const { isCanonical } = useBranding();

// 3. Select Layout based on Branding
const layoutComponent = computed(() =>
  isCanonical.value ? CanonicalLayout : BrandedLayout
);
</script>
```


3. The Layouts (The Visual Dimension)
This resolves your table. The CreateSecretForm is identical in both; only the surrounding context changes.

A. layouts/CanonicalHome.vue (Open + Canonical)

Role: Explain the product + provide the form.
Content: Large Typography, SEO Text, "Keep your secrets safe", <slot />.
B. layouts/BrandedHome.vue (Open + Branded)

Role: Reinforce trust + provide the form.
Content: Company Logo, specific instructions (e.g., "Secure message for Acme Corp employees"), <slot />.
C. views/AccessDenied.vue (External)

Role: Block access.
Content: "This installation is private." (This handles the bottom-right cell of your matrix).
4. Why this is robust
By separating the Gatekeeper (Homepage Mode) from the Decorator (Branding), you handle edge cases cleanly:

Internal Mode:

This is just "Open" but with a restricted audience.
useHomepageMode() checks the config. If config.mode === 'internal', it returns isDisabled: false (shows the form), but perhaps passes a prop showInternalWarning: true.
The CreateSecretForm receives this prop and might add a banner: "Internal Use Only - Logged IP."
The "Partial" Brand:

If a user is on the Canonical site (onetimesecret.com) but the Homepage Mode is set to "Maintenance" (a form of External), the AccessDenied component takes over before the Branding logic even runs.
Summary
File Location: apps/secret/conceal/Homepage.vue
Responsibility: Orchestrating the intersection of Homepage Mode Config and Runtime Branding.
Outcome: A single CreateSecretForm component reused across all valid states, wrapped in the appropriate context.



## Related Documents

- **[Request Lifecycle](./request-lifecycle.md)** — Explains the shift from routing-branch to adaptive-rendering pattern
- **[Secret Lifecycle](./secret-lifecycle.md)** — FSM pattern separating environmental context from entity state
- **[URI Path Mapping](./uri-paths-to-views-structure.md)** — Complete URL → Vue component mapping table
