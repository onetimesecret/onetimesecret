# docs/specs/diagnostics/diagnostics-boundary-concepts.md

---

# Deferred diagnostics boundary concepts

## created: 2026-08-22

This forward-looking inventory preserves concepts intentionally left out of the
current diagnostics implementation. It is not an implementation guide or a
record of a historical branch. Reassess each item against the current codebase
before starting work.

## Deferred concepts

- **Value-free schema failure projection:** expose schema names, paths, and
  issue codes without forwarding payload-derived values.
- **Route-template context:** provide explicit route templates for diagnostics
  instead of relying on URL scrubbers to normalize selected sensitive paths.
- **Metadata-only breadcrumbs and free-text shape scrubbing:** apply a
  restrictive breadcrumb policy and scrub opaque identifiers in diagnostics
  text.
- **Diagnostics field and resource-reference registries:** define the metadata
  allowed to reach diagnostics and the resources eligible for pseudonymous
  references.
- **Boundary acceptance tests:** add end-to-end checks for allowed diagnostics
  surfaces and leakage prevention as the deferred mechanisms land.
- **Organization correlation:** complete the frontend response contract and a
  narrowly scoped Sentry tag consumer before treating `organization_ref` as an
  active diagnostics feature. The current frontend discards the backend field.
- **Canonical diagnostics architecture documentation:** document any deferred
  mechanism only when it is implemented and supported.

Each item is independently revisit-able. Changes should use the current
`actor_ref` / `actor_scope` bootstrap contract and current diagnostics guides
as their starting point.
