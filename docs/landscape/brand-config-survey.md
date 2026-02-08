# Brand Configuration Surface Survey: Rallly, Zitadel, Documenso

## The Question

When an operator sits down to brand the thing, what do they actually touch?

Three projects, five questions each. The goal is to identify what pattern OTS should follow for its `BrandConfig` object.

---

## 1. Rallly

### Configuration Object

Scattered across three sources with no unifying object.

A TypeScript `BrandingConfig` interface defines the shape (`apps/web/src/features/branding/client.tsx`):

```
BrandingConfig {
  primaryColor: { light, dark }
  logo: { light, dark }
  logoIcon: string
  hideAttribution: boolean
  appName: string
}
```

But this interface is populated from **environment variables** parsed at startup (`apps/web/src/env.ts`): `APP_NAME`, `PRIMARY_COLOR`, `PRIMARY_COLOR_DARK`, `LOGO_URL`, `LOGO_URL_DARK`, `LOGO_ICON_URL`, `HIDE_ATTRIBUTION`. A `whiteLabelAddon` boolean on the `InstanceLicense` Prisma model gates access. The `InstanceSettings` table exists (singleton, id=1, enforced by a Postgres trigger) but currently holds only `disableUserRegistration`. Branding fields haven't migrated into it yet.

### Population

Environment variables only. The Control Panel at `/control-panel/branding` exists but every input is `<Input readOnly />` and every switch is `<Switch disabled />`. Each field shows a message: "This value can be changed by setting the `<env />` environment variable." Changing branding requires redeployment.

The bridge between "deploy-time env var" and "change later in UI" does not exist yet. The infrastructure for it is partially in place (the singleton settings table, the license gate, the readonly UI), but the mutation path from form to database to runtime config is unbuilt.

### Rendering Pipeline

Clean two-stage pipeline. `getInstanceBrandingConfig()` (cached per request) reads env vars and applies `adjustColorForContrast()` to auto-derive the dark variant. The root layout (`app/[locale]/layout.tsx`) injects four CSS custom properties onto `<html>`:

```
--primary-light, --primary-light-foreground
--primary-dark, --primary-dark-foreground
```

Tailwind consumes these via the shared stylesheet (`packages/tailwind-config/shared-styles.css`): `:root { --primary: var(--primary-light, var(--color-indigo-600)); }` with dark mode override. `bg-primary`, `text-primary` etc. all resolve through this chain. Logos render as `<img>` tags with `dark:hidden` / `dark:block` toggling.

### Not-Configured Handling

Defaults defined as constants (`features/branding/constants.ts`): indigo-600, bundled SVG logos, "Rallly" as name. Dark color auto-derived from light via iterative contrast adjustment (targets 3.0+ WCAG AA ratio, up to 20 iterations). Dark logo falls back to light logo before falling back to default dark logo. Self-hosted instances without `whiteLabelAddon` license get hard defaults regardless of env vars.

### Migration Story

No database fields to migrate. Adding new branding = adding new env var + constant default + `?? fallback` in the config function. This works precisely because nothing is in the database yet. The migration story for the eventual database-backed branding remains unwritten.

---

## 2. Zitadel

### Configuration Object

Single unified domain object with total discipline.

`LabelPolicy` is one Go struct (`internal/domain/policy_label.go`), one protobuf message (`proto/zitadel/policy.proto`), one projection table (`projections.label_policies3`). The struct holds: 4 light-theme colors (primary, background, warn, font), 4 dark-theme colors, light/dark logo URLs, light/dark icon URLs, a custom font URL, and behavioral flags (hide login name suffix, disable watermark, error popup, theme mode). The `State` field tracks lifecycle: Unspecified(0), Active(1), Removed(2), Preview(3).

The projection table's primary key is `(instance_id, id, state)`, which means both an active and a preview version of the same policy can coexist in the database simultaneously.

Color validation enforces hex format via regex: `^$|^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$`.

### Population

Pure API. No env vars, no config files. The Management API exposes the full lifecycle via gRPC:

- `AddCustomLabelPolicy` — creates a new policy in Preview state
- `UpdateCustomLabelPolicy` — modifies the preview
- `ActivateCustomLabelPolicy` — promotes preview to active
- `ResetLabelPolicyToDefault` — removes org policy, falls back to instance
- Per-asset removal: `RemoveCustomLabelPolicyLogo`, `...LogoDark`, `...Icon`, `...IconDark`, `...Font`

The Angular console component (`console/src/app/modules/policies/private-labeling-policy/`) renders both active and preview states, with logo upload via drag-and-drop. Everything persists to the eventstore immediately. No redeployment.

The draft/preview/activate lifecycle is the standout design choice. An operator can iterate on branding without affecting live users. The preview state gets its own query path (`GetPreviewLabelPolicy`). Only `ActivateCustomLabelPolicy` flips the switch.

### Rendering Pipeline

Four-stage pipeline, more complex than Rallly but driven by a single activation trigger.

When `LabelPolicyActivatedEvent` fires, a styling handler (`internal/admin/repository/eventsourcing/handler/styling.go`) generates a CSS file. For each of the 4 color axes, it produces an 11-shade palette (50 through 900 plus contrast) and emits CSS variables: `--zitadel-color-primary-500`, `--zitadel-color-warn-600`, etc. Dark theme gets its own `.lgn-dark-theme {}` block. Custom fonts get `@font-face` rules. The generated CSS uploads to asset storage.

The login renderer (`internal/api/ui/login/renderer.go`) injects a `<link>` to this generated CSS file (with `?v=` cache-bust from the policy's `ChangeDate`). Logos and icons serve through a dynamic resource handler that resolves org vs. instance assets based on request context.

The key property: CSS generation happens once on activation, not per request. The generated file is static until the next activation.

### Not-Configured Handling

Three-tier inheritance: org active → instance active → hardcoded SCSS.

The query `ActiveLabelPolicyByOrg` issues a single SQL query matching both org ID and instance ID, ordering by `is_default` (org policies have `is_default=false`, instance has `true`), `LIMIT 1`. Org wins if it exists. If removed, the query naturally falls through to instance.

Empty/unset color fields are silently omitted from the generated CSS. The base SCSS stylesheet provides fallbacks. Partial configuration is fine: set primary color but skip warn color, and warn defaults to whatever the SCSS defines.

### Migration Story

Event sourcing makes this unusually clean. New field gets added to the protobuf message, domain struct, event types (using pointer fields for change detection on `ChangedEvent`), projection columns, and API converters. Historical events in the eventstore deserialize with zero values for the new field. The projection handler re-processes all events and projects with the new column defaulting to empty/false. No SQL migration file needed for the projection; the declarative schema initialization handles column creation. The only required migration is schema-level, and it's idempotent.

---

## 3. Documenso

### Configuration Object

Dual-model with explicit inheritance semantics.

`OrganisationGlobalSettings` (Prisma model) holds branding at org level with non-nullable fields and defaults:

```
brandingEnabled        Boolean @default(false)
brandingLogo           String  @default("")
brandingUrl            String  @default("")
brandingCompanyDetails String  @default("")
```

`TeamGlobalSettings` mirrors the same fields but **nullable**:

```
brandingEnabled        Boolean?
brandingLogo           String?
brandingUrl            String?
brandingCompanyDetails String?
```

`null` on the team means "inherit from org." The resolution function `extractDerivedTeamSettings()` (`packages/lib/utils/teams.ts`) iterates all keys and overwrites org values with non-null team values. However, the branding inheritance is all-or-nothing: `getTeamSettings()` checks `teamSettings.brandingEnabled === null` and if so, copies all four branding fields from org. No partial inheritance per-field.

### Population

Admin UI forms backed by tRPC mutations. The org branding page (`routes/_authenticated+/o.$orgUrl.settings.branding.tsx`) calls `updateOrganisationSettings` via tRPC. Logo upload uses `putFile()`, stores result as JSON-stringified file reference. Team branding page has a three-way select for `brandingEnabled`: Yes / No / "Inherit from organisation" (which stores `null`).

Everything writes to PostgreSQL. Fully runtime-configurable, no env vars involved. Feature-gated by `organisationClaim.flags.allowCustomBranding` (subscription plan check). Free plans see an alert directing them to Teams+ tier.

### Rendering Pipeline

Multi-path, not a single pipeline.

**Emails**: A React context provider (`BrandingProvider` in `packages/email/providers/branding.tsx`) wraps email templates. Components like `TemplateFooter` call `useBranding()` and conditionally render custom company details or default Documenso footer. The "Powered by Documenso" line is controlled by `brandingHidePoweredBy`.

**Signing pages**: The signer header component checks `envelopeData.settings.brandingEnabled && envelopeData.settings.brandingLogo` and either renders an `<img>` pointing at `/api/branding/logo/team/{teamId}` or falls back to the default logo.

**Logo API**: Dedicated endpoints per level (`/api/branding/logo/team/$teamId`, `/api/branding/logo/organisation/$orgId`). These call `getTeamSettings()` (which triggers inheritance resolution), verify `brandingEnabled`, parse the JSON-stored logo reference, fetch from file storage, and serve with 1-hour cache + 24-hour stale-while-revalidate.

No CSS variable generation. Branding is primarily about logos and footer text, not color theming.

### Not-Configured Handling

Schema defaults provide the bottom layer: `brandingEnabled=false`, everything else empty string. Team defaults to all-null via `generateDefaultTeamSettings()`. The inheritance chain: team explicit value → org value → schema default. Since `brandingEnabled` defaults to `false`, an unconfigured installation shows stock Documenso branding everywhere. The email footer has three branches: custom details (if branding enabled + details present), default Documenso footer (if branding disabled), or nothing (branding enabled but no details provided, which is an implicit gap).

### Migration Story

Prisma migrations with `DEFAULT` clauses. The initial branding migration (`20241107034521`) added columns to `TeamGlobalSettings` with `NOT NULL DEFAULT false`/`DEFAULT ''`. The later org refactor (`20250522054050`) created `OrganisationGlobalSettings` with the same defaults, then altered `TeamGlobalSettings` to make branding fields nullable (dropping `NOT NULL` and `DEFAULT`), enabling inheritance. Existing teams that had non-null values retained them; new teams default to null. New installations auto-populate via `INSERT INTO ... SELECT` during migration.

Adding a future branding field follows the pattern: add non-nullable with default to org, add nullable to team, update `generateDefaultTeamSettings()`, update the inheritance resolution in `getTeamSettings()`, update the context type.

---

## Cross-Cutting Patterns

### Configuration Object Shape

| Project | Object | Shape | Lifecycle |
|---------|--------|-------|-----------|
| Rallly | `BrandingConfig` interface + env vars | Flat bag of independent values | None (deploy-time only) |
| Zitadel | `LabelPolicy` domain object | Single struct, one table, one protobuf | Draft → Preview → Active |
| Documenso | `OrganisationGlobalSettings` + `TeamGlobalSettings` | Two-level model with nullable inheritance | Immediate (save = live) |

The pattern is clear: Zitadel treats branding as a first-class domain object with a defined lifecycle. Documenso treats it as a settings block with inheritance. Rallly treats it as deployment configuration.

### The Single-Object Question

Zitadel's `LabelPolicy` demonstrates what a single object buys you: the preview/activate lifecycle falls out naturally (it's just a state field on the same object), the API is one resource with predictable CRUD, the rendering pipeline has one trigger point (activation event → regenerate CSS), and the inheritance model is straightforward (org policy shadows instance policy at query time).

Documenso's dual-model approach is an honest response to a real requirement (org vs. team override), but the inheritance logic is handwritten and all-or-nothing. The rendering pipeline fragments across email context, API endpoints, and component-level checks because there's no single "brand resolved" event.

Rallly's env-var approach is the simplest starting point but demonstrably incomplete. The readonly admin UI is an admission that the bridge from deployment config to runtime config needs building.

### What Gets Configured

| Field Category | Rallly | Zitadel | Documenso |
|---------------|--------|---------|-----------|
| Primary/brand color | Yes (hex + auto dark) | Yes (4 light + 4 dark, 11-shade palette each) | No |
| Logo (light/dark) | Yes | Yes (+ icon light/dark) | Yes (single, no dark variant) |
| Favicon/icon | Yes (logoIcon) | Yes (separate from logo) | No |
| Product/app name | Yes | No (separate i18n) | No |
| Custom font | No | Yes (uploaded, @font-face generated) | No |
| Footer/attribution | Yes (hide toggle) | Yes (watermark toggle) | Yes (company details + powered-by toggle) |
| Theme mode | No | Yes (auto/light/dark) | No |
| Email sender branding | No | No | Yes (DKIM domain verification) |

### Rendering Approach

Rallly and Zitadel both land on CSS custom properties as the mechanism, but at different scales. Rallly injects 4 properties per request. Zitadel generates 44+ properties (11 shades × 4 color axes) once on activation and serves the static file. Both use the same fundamental idea: stored config → CSS vars → existing utility classes/styles resolve differently.

Documenso doesn't do CSS theming at all. Its branding is asset substitution (logo swap) and content injection (footer text). This makes sense for a document signing tool where the "branded" surface is primarily emails and the signing page, not a full application UI.

### The Deploy-Time vs. Runtime Split

This is the most instructive axis:

- **Rallly**: Deploy-time only. The UI exists but is readonly. The mutation path is unbuilt.
- **Zitadel**: Runtime only. No env vars. Everything through API. The preview/activate lifecycle provides safety.
- **Documenso**: Runtime only. Form → tRPC → database. Changes go live immediately (no preview).

The hybrid approach (env vars as initial seed, database as runtime override, UI as mutation surface) is what Rallly is heading toward but hasn't reached. Zitadel skipped the hybrid phase entirely and went straight to API-first. Documenso never had an env-var phase; it launched branding directly into the database.

### What the Survey Adds Beyond the Guide's Hypotheses

**Rallly's bridge is further from built than expected.** The guide suggested searching for how they bridge deploy-time env vars to runtime UI changes. They don't. The readonly UI with "set the env var" messages is the current state. The `InstanceSettings` singleton table exists but holds zero branding fields. Rallly is less "closest analog" and more "cautionary tale about stopping at env vars."

**Zitadel's activation trigger matters more than its lifecycle.** The guide emphasized draft/preview/activate as the key design choice. For single-tenant self-hosted deployments, preview is ceremony. What matters is that activation is the moment CSS generation happens. One event, one static artifact, done. OTS currently regenerates the 44-var palette per request. An activation trigger (even if "activation" is just "save") would let that generation happen once.

**Documenso's inheritance is cruder than the schema suggests.** The guide pointed to nullable fields as "null means inherit." True at the field level, but the resolution function treats branding as all-or-nothing: if `brandingEnabled` is null at team level, it copies all four branding fields from org wholesale. No per-field inheritance despite the schema supporting it. The schema is more expressive than the code that reads it.

**The gap nobody handles well: email sender branding.** Documenso has DKIM domain verification for custom email sender. Zitadel and Rallly don't touch it. If custom domains are a first-class feature, email sender identity is part of the brand surface and none of these three provide a clean model for it.
