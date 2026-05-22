# docs/specs/secret-creation-flows.md
---
# Secret Creation Flows

Behavioral specification for the post-submit navigation flows of the secret
creation forms. Three flows exist; this document records what controls each and
how they differ, ahead of any consolidation work.

## Overview

| Flow | What happens after submit | Control point |
|---|---|---|
| Two-page | Navigate to `/receipt/:identifier` | `workspaceMode = false` (default) |
| Workspace (one-page) | Stay in place, `RecentSecretsTable` refreshes inline | `workspaceMode = true` |
| Incoming | Navigate `/incoming` → `/incoming/:receiptKey` | unconditional |

The "one-page" flow is **not a modal**. It is the form resetting in place with
an inline table refresh. The Incoming flow is **not a modal either** — it is a
two-route page swap styled to *look* like a modal dialog (centered
`max-w-3xl` card with `rounded-2xl shadow-lg`), with no backdrop, no `<dialog>`,
no `Teleport`, no focus trap, and no Esc-to-dismiss.

## Flow Selection

`workspaceMode` is a client-side preference only — a boolean in `localStorage`
under key `onetimeWorkspaceMode`. There is no server config flag for it. It
persists across sessions (not `sessionStorage`).

| Entry point | Form component | `workspaceMode` source | Resulting flow |
|---|---|---|---|
| `/` (standard) | `SecretForm` | prop from `localReceiptStore` via `HomepageContent` | two-page or workspace |
| `/` (custom domain) | `SecretForm` | prop omitted → defaults `false` | always two-page |
| `/dashboard` | `WorkspaceSecretForm` | reads `localReceiptStore` directly | two-page or workspace |
| `/incoming` | `IncomingForm` | n/a | always two-page (Incoming) |

## Navigation Decision Matrix

The navigation branch lives in each form's `onSuccess` callback, **not** in the
shared `useSecretConcealer` composable — the composable only invokes
`onSuccess` and returns.

| Form | Action | `workspaceMode` | Result |
|---|---|---|---|
| `SecretForm` | any | `false` | `router.push('/receipt/:id')` |
| `SecretForm` | any | `true` | stay in place |
| `WorkspaceSecretForm` | `create-link` | `false` | `router.push('/receipt/:id')` |
| `WorkspaceSecretForm` | `create-link` | `true` | stay in place |
| `WorkspaceSecretForm` | `generate-password` | any | `router.push('/receipt/:id')` — always navigates |
| `IncomingForm` | submit | n/a | `router.push({name:'IncomingSuccess'})` |

`generate-password` in the workspace form always navigates regardless of
`workspaceMode`.

## Incoming Flow Routes

| Route | Name | Component |
|---|---|---|
| `/incoming` | `IncomingSecretForm` | `IncomingForm` |
| `/incoming/:receiptKey` | `IncomingSuccess` | `IncomingSuccess` |

Submit navigates form → success page. "Create another" on the success page
navigates back to `IncomingSecretForm`. Page content does not persist across
either transition — each is a full route swap.

## Consolidation Notes

- Nothing architectural blocks workspace mode on the standard homepage:
  `HomepageContent` already reads and passes `localReceiptStore.workspaceMode`,
  and the workspace toggle checkbox already exists in `RecentSecretsTable`.
- `BrandedHomepage` hardcodes two-page (omits the `workspaceMode` prop) —
  workspace mode can never activate on custom domains without a change there.
- A *true* modal+same-page experience (receipt rendered in an overlay over a
  persisting form) does not exist anywhere today. The Incoming card styling can
  be reused for the shell, but the modal mechanics would be net-new.
- `views/incoming/IncomingSecretForm.vue` and `IncomingSuccessView.vue` are
  orphaned duplicates — no router references them; safe to delete.

## Implementation References

- `localReceiptStore` — `workspaceMode` state and `localStorage` persistence
- `SecretForm.vue` — homepage form, `onSuccess` nav branch
- `WorkspaceSecretForm.vue` — dashboard form, `onSuccess` nav branch
- `useSecretConcealer` — shared submission orchestrator (no routing)
- `useIncomingSecret` — Incoming orchestration and default navigation
- `IncomingForm.vue` / `IncomingSuccess.vue` — live Incoming views
