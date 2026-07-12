I traced `homepage_mode` end-to-end (config → `HomepageModeHelpers` → `initialize_view_vars` → `ConfigSerializer` → bootstrap → Vue router). The clearest path to simplification comes from what the trace shows: most of the machinery has no user-visible effect.

**What the feature actually does today**

The only consumer of `homepage_mode` in the frontend is one line in `src/router/public.routes.ts`:

```ts
if (!hasSession && (bootstrapStore.authentication?.required || bootstrapStore.homepage_mode === 'external'))
  return 'disabled-homepage';
```

That's it. Which means:

- `mode: external` — matched visitors see the disabled homepage. This is the one real behavior, and it's the *same branch* as `authentication.required`.
- `mode: internal` — a complete no-op. Matched visitors get `'internal'`, unmatched get `nil` → `'open'`, and both render the normal homepage. The `useHomepageMode` composable (with `isInternal` / `showInternalWarning`) is defined but imported by zero components.
- The design can't even express the use case people actually want ("my office sees the form, the public sees the info page"), because non-matching visitors always fall through to the default homepage. `external` + CIDRs is effectively a UI *blocklist* for specific networks, which is a strange thing to want.

Meanwhile the cost side is large: three knobs (`mode`, `matching_cidrs`, `mode_header`), a documented two-step detection priority, /24 / /48 privacy prefix rules that reject CIDRs *silently at request time* (log-only), a spoofable header fallback (any visitor can send `O-Homepage-Mode: external` themselves), the implicit dependency on `site.network.trusted_proxy` for IP resolution, ~190 lines of helper code, seven-ish test files, and conceptual overlap with `authentication.required`, `ui.enabled`, `disabled_variant`, and the per-domain `HomepageConfig`.

**Recommendation: delete the detection machinery, keep the one real behavior**

Replace the trio with a single declarative setting that says what the operator actually controls:

```yaml
homepage:
  # Who sees the secret-creation form on the canonical domain.
  # public (default) — everyone. gated — sessionless visitors get the
  # disabled variant instead (same rendering path as authentication.required).
  secret_form: <%= ENV['HOMEPAGE_SECRET_FORM'] || 'public' %>
  disabled_variant: ...
  public_links: ...
```

Then go one step further and stop re-deriving policy in the frontend: have the backend serialize a single computed boolean (`homepage_gated = auth.required || secret_form == 'gated'`) so the router checks one flag instead of two config fields. That removes the `trusted_proxies` interaction *entirely* — no IP matching, no proxy-depth caveats, no privacy-prefix rules, no header normalization. `HomepageModeHelpers`, its specs, and the CIDR docs all go away, and the `homepage_modes.example.yaml` shrinks to three lines.

For migration, follow the precedent you already have in `Config#normalize_brand` (#3612's `header.branding` fallback): a normalizer in `after_load` that maps `mode: external` → `secret_form: gated` with a deprecation log, warns that `mode: internal` was a no-op and is ignored, and warns that `matching_cidrs`/`mode_header` are no longer honored.

**If CIDR gating must survive**

Only if you know someone relies on network detection, keep it — but inverted into the shape people actually want, as an *exemption* from gating:

```yaml
homepage:
  secret_form: gated
  exempt_networks: ["10.0.0.0/8", "203.0.113.0/24"]  # these still see the form
```

Two rules make this sane where the current version isn't: validate CIDRs at **boot** and fail or warn loudly (not silent per-request rejection), and document the `trusted_proxy` dependency in exactly one place — a one-line comment on `exempt_networks` pointing at `site.network.trusted_proxy`. I'd drop the header fallback either way; it's client-spoofable by design, and an operator whose edge can inject headers can gate at the edge properly.

One heads-up: your `.claude/worktrees/domain-validation-acme-notes` worktree contains in-progress work that *adds* to this feature (`homepage_bypass_header` tries, more mode helpers tests), so if that lands first, the deletion surface grows — worth deciding the direction before merging it.

Happy to implement this — the full removal (option 1, with the migration shim and test cleanup) is a well-contained change. Want me to draft it as a plan or start on a branch?
