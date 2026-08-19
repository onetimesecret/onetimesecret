/**
 * Composable for footer configuration derived from bootstrap store.
 *
 * Centralizes access to deployment-level footer settings (e.g., show_version)
 * so all footer components respect the same server config.
 */
import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { storeToRefs } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

export function useFooterConfig() {
  const bootstrapStore = useBootstrapStore();
  const { ui, authenticated } = storeToRefs(bootstrapStore);

  /**
   * Whether to show version info in footer.
   * Controlled by FOOTER_VERSION_ENABLED env var via ui.show_version.
   * Defaults to true when not configured.
   */
  const showVersionConfig = computed(() => ui.value?.show_version ?? true);

  /**
   * Whether to render the version string in the footer.
   * Exposing the exact deployment version to anonymous visitors makes it
   * easier to fingerprint the install and target known CVEs, so this is
   * additionally restricted to authenticated sessions.
   */
  const showVersion = computed(() => showVersionConfig.value && authenticated.value === true);

  return {
    showVersionConfig,
    showVersion,
  };
}

/** Per-component inputs to {@link useFooterAnchor}. */
export interface FooterAnchorOptions {
  /** The consuming footer's `displayVersion` layout prop. */
  displayVersion: MaybeRefOrGetter<boolean>;
  /** The consuming footer's `displayPoweredBy` layout prop. */
  displayPoweredBy: MaybeRefOrGetter<boolean>;
}

/**
 * Resolves what occupies the LEFT cell of a footer's bottom bar.
 *
 * WHY this exists: that bar is a two-ended flex row — `justify-between` with
 * the version/attribution cell on one end and the toggle cluster (region,
 * theme, language, feedback) on the other. It only reads as a bar when BOTH
 * ends are occupied. Its two possible left-hand occupants are now each
 * conditional and frequently both off at once:
 *
 *   - the version string is authenticated-only (see `showVersion` above), so
 *     it is absent on every anonymous surface; and
 *   - `displayPoweredBy` is an explicit opt-in that App.vue defaults to
 *     `false` and most route metas leave off.
 *
 * The result was an empty left cell with the toggles pinned to a bare right
 * edge. Rather than flip `displayPoweredBy` on across App.vue and ~15 route
 * metas — which would destroy the flag's opt-in meaning and silently regress
 * for any route added later that omits it — the invariant is enforced here,
 * in the footer layer where the lop-sidedness actually lives: the existing
 * attribution falls back in as a brand anchor whenever nothing else would
 * occupy the cell. No new i18n strings, no new markup.
 *
 * WHITE-LABEL GUARD: the attribution interpolates `brand_product_name`, which
 * `initialize_view_vars.rb` derives from the INSTALL's `OT.conf['brand']
 * ['product_name']` — it is never the tenant's name. Rendering it as an
 * unrequested fallback on a custom domain would therefore stamp the
 * operator's identity onto a customer's white-labelled page (the same A3
 * identity leak `identityStore.showPlatformIdentity` guards for the
 * masthead). So the fallback is suppressed on custom domains; an explicit
 * `displayPoweredBy: true` still wins there, preserving the deliberate
 * attribution the custom-domain route overrides already opt into
 * (public.routes.ts, apps/secret/routes/receipt.ts). Reading
 * `domain_strategy` off the bootstrap store rather than `useProductIdentity`
 * keeps this composable free of that store's i18n-context requirement,
 * matching how the router guards read the same field.
 */
export function useFooterAnchor(opts: FooterAnchorOptions) {
  const { showVersion: versionPermitted } = useFooterConfig();
  const { domain_strategy } = storeToRefs(useBootstrapStore());

  /** True on a tenant's white-labelled domain. Mirrors identityStore.isCustom. */
  const isCustomDomain = computed(() => domain_strategy.value === 'custom');

  /** Version string: deployment config AND authenticated AND the layout asked. */
  const showVersion = computed(
    () => versionPermitted.value && toValue(opts.displayVersion) === true
  );

  /**
   * Attribution: rendered when the layout asked for it, OR as the fallback
   * anchor when the left cell would otherwise be empty (canonical/subdomain
   * only — see the white-label guard above).
   */
  const showPoweredBy = computed(
    () =>
      toValue(opts.displayPoweredBy) === true ||
      (!showVersion.value && !isCustomDomain.value)
  );

  /** The `-` / `•` divider only earns its place between two occupants. */
  const showSeparator = computed(() => showVersion.value && showPoweredBy.value);

  /**
   * Whether the left cell has ANY occupant.
   *
   * False only where the white-label guard above deliberately withholds the
   * fallback: an anonymous visitor on a custom domain (e.g. that tenant's
   * /signin, which `src/apps/session/routes.ts` leaves at App.vue's
   * `displayPoweredBy: false`). Consumers bind the bar's justification to
   * this — with nothing on the left, `justify-between` would strand the
   * toggle cluster against a bare edge, so the bar centers instead. That is
   * the fallback-of-the-fallback: it costs no strings and leaks no branding.
   */
  const hasAnchor = computed(() => showVersion.value || showPoweredBy.value);

  return {
    showVersion,
    showPoweredBy,
    showSeparator,
    hasAnchor,
    isCustomDomain,
  };
}
