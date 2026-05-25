# Frontend Architecture

Vue 3 SPA. Routes flow into one of four apps under `src/apps/`; cross-cutting code lives in `src/shared/`.

> **Design Principle**: a "Pit of Success". Make it hard to put code in the wrong place.

## Layout Convention

Each app directory mirrors the top-level `src/` layout:

```
apps/<app>/
├── views/         # Page-level Vue components
├── components/    # App-private components
├── composables/   # App-private composables
├── layouts/       # App-private layouts
└── routes.ts      # Route definitions
```

`apps/colonel/` and `apps/session/` are the reference implementations. `apps/workspace/` and `apps/secret/` still carry residual feature folders (e.g. `secret/conceal`, `workspace/billing`) standing in for parts of `views/`. New code should land in `views/`; existing feature folders fold in when touched.

## The Four Apps

| App         | Purpose                                                | Auth     |
|-------------|--------------------------------------------------------|----------|
| `secret`    | Create and reveal secrets (the transactional core)     | Mixed    |
| `workspace` | Dashboard, account, billing, organizations, domains    | Required |
| `session`   | Sign-in, sign-up, MFA, password reset                  | Public   |
| `colonel`   | System administration                                  | Colonel  |

Route composition and load order live in `src/router/index.ts`; first match wins.

## Shared Resources

`src/shared/` holds cross-app primitives (`components/`, `composables/`, `layouts/`, `stores/`). Promote code here only when more than one app needs it. Anything used by exactly one app stays inside that app.

## Conceptual Dimensions

Several independent dimensions control how a view renders. Conflating them was the source of past architectural confusion.

| Dimension        | Binds at        | Question                       | Role                          |
|------------------|-----------------|--------------------------------|-------------------------------|
| Interaction Mode | Design-time     | What is the user doing?        | Router selects the app        |
| Domain Context   | Runtime         | How should it look?            | Wrapper adapts presentation   |
| Domain Scope     | Session         | Which domain am I managing?    | Filter scopes Workspace       |
| Homepage Mode    | Deployment-time | Is creation permitted?         | Gatekeeper for `/`            |

**Domain Context** is detected per-request from the request host: `Canonical` (config-defined) or `Custom` (per-domain branding). Each custom domain belongs to one organization and carries its own brand config.

**Domain Scope** (Workspace only) elevates Domain Context into a persistent management scope. Privacy defaults and new-secret creation flow through the selected domain for the duration of the session.

**Homepage Mode** gates `/`:

| Mode     | Who can create       | Who can view | Homepage shows        |
|----------|----------------------|--------------|-----------------------|
| Open     | Anyone               | Anyone       | Form + explainer      |
| Internal | Internal IPs/headers | Anyone       | Form + explainer      |
| External | Nobody               | Anyone       | "Nothing to see here" |

## Actor Roles

Three role systems apply at different layers. Do not conflate them.

- **Transaction roles** (resolved by `useSecretContext`): `CREATOR`, `RECIPIENT_AUTH`, `RECIPIENT_ANON`. Answers "who are you relative to *this secret*?". `CREATOR` is singular by design; recipient variance is intentional.
- **Organization roles**: `OWNER`, `ADMIN`, `MEMBER`. Standard RBAC inside Workspace.
- **Account roles** (`CustomerRole`): `CUSTOMER`, `COLONEL`, `RECIPIENT`, `USER_DELETED_SELF`. Global account type; `COLONEL` grants `/colonel/*` access.

| Concern        | Secret App                  | Workspace App      |
|----------------|-----------------------------|--------------------|
| Auth variance  | High (anon, auth, owner)    | Low (always auth)  |
| Logic model    | Dimensional matrix          | Standard RBAC      |

## Naming Conventions

PascalCase for Vue components, layouts, stores, views (`UserProfile.vue`). kebab-case for non-Vue utilities (`color-utils.ts`). Suffixes signal purpose: `.routes.ts`, `Store.ts`, `.spec.ts`, `.fixture.ts`, `.d.ts`.

## Notes

- `/receipt/:receiptIdentifier` lives in the Secret app, not Workspace. It requires "ownership" but ownership here is historically the unguessable URL, not authentication; the interaction is still transactional.
- Workspace imports brand *data* (to populate forms) but not brand *presentation logic* (Workspace is always OTS-branded). Presentation lives under the Secret app.

## See Also

- [`src/router/index.ts`](./router/index.ts), route composition and ordering
- [`../docs/product/secret-lifecycle.md`](../docs/product/secret-lifecycle.md), secret state FSM
- `package.json`, dev/build/test/lint commands
