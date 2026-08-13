<!-- src/apps/workspace/components/domains/DomainSigninConfigForm.vue -->

<script setup lang="ts">
  /**
   * Domain Sign-In Configuration Form
   *
   * Presentational component for per-domain signin overrides. Three modes,
   * switched by a 3-segment control:
   *
   * - "Any available method" (signin_enabled && restrict_to === null): the
   *   sign-in page shows every globally-available method. Email / SSO carry
   *   per-domain availability toggles (AND semantics — a domain can only
   *   narrow a global method).
   *
   * - "One specific method" (signin_enabled && restrict_to !== null): the
   *   sign-in page shows ONLY the chosen method. No availability toggles here,
   *   so "restrict to X while X disabled" is unexpressible. Picking a method
   *   also flips that method's availability flag on (the login page gates
   *   restrict_to through the same availability resolution), committed
   *   atomically in one PUT.
   *
   * - "Sign-in disabled" (signin_enabled === false): no sign-in at all on this
   *   domain. The public sign-in page shows a "not available" notice and POST
   *   /signin is blocked server-side. restrict_to and the availability flags
   *   are preserved so switching back restores the previous setup.
   *
   * Only globally-available methods are offered in either method mode —
   * otherwise a restrict_to value with no backing method would yield a blank
   * login page. SSO is additionally gated on the manage-SSO entitlement
   * (canManageSso): without it the org cannot configure SSO credentials, so
   * enabling or restricting to SSO could never produce a working method — the
   * toggle and radio render locked instead.
   *
   * Everything auto-saves (PUT is full-replacement); there is no Save button.
   *
   * Materialize-on-touch (ADR-024): while the domain follows workspace
   * defaults the form shows the SEEDED inherited state, and any click on a
   * mode or method — even one matching what is already shown — persists an
   * explicit override (the composable forces `enabled: true` on every save).
   * That's why the no-change early-returns are bypassed when
   * `workspaceDefault` is true: the value may not change, but the pin must.
   */
  import type {
    EffectiveRestrictTo,
    TenantSsoVerdict,
  } from '@/schemas/api/domains/responses/signin-config';
  import type { SigninRestrictTo } from '@/schemas/shapes/domains/signin-config';
  import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
  import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { SigninConfigFormState } from '@/shared/composables/useSigninConfig';
  import { isOrgsSsoEnabled } from '@/utils/features';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  // ---------------------------------------------------------------------------
  // Props
  // ---------------------------------------------------------------------------

  const props = defineProps<{
    domainExtId: string;
    formState: SigninConfigFormState;
    isLoading: boolean;
    isSaving: boolean;
    isDeleting: boolean;
    isConfigured: boolean;
    /**
     * True while the domain follows workspace defaults (no explicit override,
     * ADR-024). The form then shows the seeded inherited state, and clicking a
     * mode/method that matches it must still save (materialize the pin) — the
     * no-change early-returns are bypassed.
     */
    workspaceDefault: boolean;
    ssoConfigured: boolean;
    /**
     * The runtime ladder's tenant-SSO verdict, serialized by the server
     * (#4111, `details.tenant_sso`). ONE authoritative field: the status line
     * below renders `available` / `unavailable_reason` verbatim and the client
     * never re-derives availability from raw flags (ADR-024). It supersedes
     * the #4107 client-side condition (`ssoConfigured && !ssoCredentialsEnabled`),
     * which could only see one rung of the ladder.
     *
     * Absent/null (older backend, or details not loaded yet) ⇒ no status line
     * and no SSO-restriction guard: there is no verdict to report, and
     * inventing one here is exactly the drift this field exists to kill.
     */
    tenantSso?: TenantSsoVerdict | null;
    /**
     * The server's restriction resolution for this domain
     * (ADR-034#resolution-is-model-owned / #settings-api-serializes-effective-restrict-to),
     * verbatim. Drives the notices for the two states a method picker cannot
     * express on its own: `unavailable` (the restriction stands but its method
     * cannot run here, so sign-in offers nothing — fail-closed,
     * ADR-034#resolution-intersects-never-widens) and
     * `source: 'conflict'` (global and domain name different methods, so
     * neither applies). Never recomputed client-side.
     */
    effectiveRestrictTo?: EffectiveRestrictTo | null;
    canManageSso: boolean;
    /**
     * Globally-available auth methods (install/global config). Gates which
     * methods are offered: a method that is off site-wide must never be
     * selectable, or restrict_to/availability would produce a blank login page.
     * Password and WebAuthn have no per-domain field; only the global flag gates
     * them. undefined upstream is treated as available (codebase convention).
     *
     * SSO is deliberately NOT a member: per-domain SSO is *tenant* SSO
     * (CustomDomain::SsoConfig credentials), gated on ORGS_SSO_ENABLED +
     * manage_sso — not on the platform AUTH_SSO_ENABLED that bootstrap
     * `features.sso` carries. See `ssoAvailable` below.
     */
    globalAvailability: { email_auth: boolean; webauthn: boolean };
    /** Field currently auto-saving, for per-toggle loading feedback. */
    savingField: keyof SigninConfigFormState | null;
  }>();

  // ---------------------------------------------------------------------------
  // Emits
  // ---------------------------------------------------------------------------

  const emit = defineEmits<{
    (e: 'delete'): void;
    (e: 'configure-sso'): void;
    /**
     * Auto-save a partial form patch (full-replacement PUT). Multi-field patches
     * (restrict_to + availability flag) commit atomically as one save.
     */
    (
      e: 'auto-save',
      partial: Partial<SigninConfigFormState>,
      savingFieldHint?: keyof SigninConfigFormState
    ): void;
  }>();

  const { t } = useI18n();

  // ---------------------------------------------------------------------------
  // Mode (derived from restrict_to + a local "intent" flag)
  // ---------------------------------------------------------------------------

  /**
   * Local intent: the user clicked "One specific method" but hasn't picked one
   * yet, so restrict_to is still null and nothing has been saved. This reveals
   * the picker without persisting. It only matters while restrict_to is null;
   * once a method is chosen (or on load with restrict_to set) the prop drives
   * the mode and this flag is irrelevant.
   */
  const oneSelectedIntent = ref(false);

  /**
   * "Sign-in disabled" wins over a preserved restrict_to: when signin_enabled
   * is false the method modes are not shown, whatever restrict_to holds.
   */
  const isModeDisabled = computed(() => props.formState.signin_enabled === false);

  const isModeOne = computed(
    () => !isModeDisabled.value && (props.formState.restrict_to !== null || oneSelectedIntent.value)
  );

  const isModeAny = computed(() => !isModeDisabled.value && !isModeOne.value);

  /** Hint paragraph under the mode switch, per active mode. */
  const modeHint = computed(() => {
    if (isModeDisabled.value) return t('web.domains.signin.mode_disabled_hint');
    if (isModeOne.value) return t('web.domains.signin.mode_one_hint');
    return t('web.domains.signin.mode_any_hint');
  });

  /**
   * "One specific method" (Mode B) in the mode switch. Was hidden pending
   * further testing while the sign-in page only honored restrict_to='sso';
   * restored once AuthMethodSelector renders all four restrict_to values.
   * Flip to `false` to withhold the segment again — the mode's logic stays
   * intact either way (a preset restrict_to still renders the picker), and
   * the sr-only stand-in radio below keeps the radiogroup accessible.
   */
  const showRestrictMode: boolean = true;

  // ---------------------------------------------------------------------------
  // Mode switch keyboard support (roving tabindex)
  // ---------------------------------------------------------------------------

  /**
   * Roving tabindex: the radiogroup is a single tab stop (the checked
   * segment); arrow keys move focus between segments. Activation stays on
   * click/Enter/Space (manual activation) — selecting a mode fires an
   * auto-save PUT, and WAI-ARIA APG recommends NOT having selection follow
   * focus when activation has side effects like network requests.
   */
  // Segment order (disabled, any, one) matches the DOM so roving tabindex and
  // arrow-key navigation stay consistent. getElementById filtering in
  // onModeKeydown skips "one" if it is ever withheld again (showRestrictMode).
  const MODE_SEGMENT_IDS = ['signin-mode-disabled', 'signin-mode-any', 'signin-mode-one'] as const;

  const checkedModeIndex = computed(() => {
    if (isModeDisabled.value) return 0;
    // Mode B ("one") is index 2, but its segment is not rendered while
    // showRestrictMode is false. A domain with a preset restrict_to still lands
    // in Mode B, so fall back to the first visible segment (0) for the roving
    // tabindex — otherwise no visible segment holds tabindex 0 and the whole
    // radiogroup drops out of the keyboard tab order. Per WAI-ARIA APG, when no
    // radio is checked the first radio takes the tab stop; each segment's
    // aria-checked stays accurate independently of this index.
    if (isModeOne.value) return showRestrictMode ? 2 : 0;
    return 1;
  });

  const modeTabindex = (index: number) => (checkedModeIndex.value === index ? 0 : -1);

  const onModeKeydown = (event: KeyboardEvent) => {
    const handled = ['ArrowRight', 'ArrowDown', 'ArrowLeft', 'ArrowUp', 'Home', 'End'];
    if (!handled.includes(event.key)) return;
    event.preventDefault();

    const segments = MODE_SEGMENT_IDS.map((id) => document.getElementById(id)).filter(
      (el): el is HTMLElement => el !== null
    );
    if (segments.length === 0) return;

    const current = segments.indexOf(document.activeElement as HTMLElement);
    let next: number;
    if (event.key === 'Home') {
      next = 0;
    } else if (event.key === 'End') {
      next = segments.length - 1;
    } else {
      const delta = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : -1;
      const from = current === -1 ? checkedModeIndex.value : current;
      next = (from + delta + segments.length) % segments.length;
    }
    segments[next].focus();
  };

  /**
   * Clear the local "intent" flag whenever restrict_to reverts to null
   * externally (e.g. Reset to defaults / parent delete). Without this the
   * lingering intent keeps isModeOne true after the config is wiped, stranding
   * the form in Mode B with no method selected instead of reverting to Mode A.
   */
  watch(
    () => props.formState.restrict_to,
    (v) => {
      if (v === null) oneSelectedIntent.value = false;
      // A restriction landing (from this form or elsewhere) settles the
      // pending question — never leave the warning stranded over a stale
      // choice.
      pendingSsoRestriction.value = false;
    }
  );

  // ---------------------------------------------------------------------------
  // Method availability (only offer globally-available methods)
  // ---------------------------------------------------------------------------

  const passwordAvailable = true; // always available
  const webauthnAvailable = computed(() => props.globalAvailability.webauthn);
  const emailAuthAvailable = computed(() => props.globalAvailability.email_auth);
  /**
   * SSO here means TENANT SSO (the domain's own SsoConfig credentials).
   * ORGS_SSO_ENABLED — with manage_sso, the pair DomainsTable and
   * OrganizationSettings gate on — governs who may CONFIGURE tenant SSO, not
   * whether it runs: the runtime ladder (SsoConfig.tenant_sso_unavailable_reason)
   * checks the SsoConfig record + sso_permitted_for?, never these management
   * gates, so don't AND runtime state with them. It is also NOT bootstrap
   * `features.sso` (platform AUTH_SSO_ENABLED, resolved against the *current
   * request's* domain): on the workspace host that reads the canonical site's
   * SSO config, which has no bearing on this domain's tenant SSO.
   */
  const ssoAvailable = computed(() => isOrgsSsoEnabled());

  /**
   * Both gates the backend enforces on every tenant-SSO write
   * (DomainsAPI::Logic::SsoConfig::Base — `manage_sso` entitlement AND the
   * `features.organizations.sso_enabled` flag). Offering "Configure" without
   * both would open a modal whose save is rejected. Mode B gets this for free
   * (the SSO row is omitted when unavailable); Mode A's static row needs it.
   */
  const ssoConfigurable = computed(() => ssoAvailable.value && props.canManageSso);

  /**
   * Tenant-SSO status line (#4111). The server answers "why isn't SSO being
   * offered on my sign-in page?" once (`SsoConfig.tenant_sso_unavailable_reason`);
   * this maps the reported rung to copy and NOTHING else — no client-side AND
   * of raw flags (ADR-024). An unrecognized rung (a newer backend) falls back
   * to the generic unavailable copy rather than rendering nothing.
   *
   * Gated on ssoConfigurable: the remedial copy points at controls
   * ("Edit credentials", the toggle above) that only render with both write
   * gates, and without them the row already names the real blocker (upgrade
   * lock / "Unavailable site-wide").
   */
  const UNAVAILABLE_REASON_COPY: Record<string, { badge: string; hint: string }> = {
    no_sso_config: {
      badge: 'web.domains.sso.status_not_configured_badge',
      hint: 'web.domains.sso.status_not_configured_hint',
    },
    // Carried over from #4107 — same rung, same copy, authoritative source.
    sso_config_disabled: {
      badge: 'web.domains.sso.connection_disabled_badge',
      hint: 'web.domains.sso.connection_disabled_hint',
    },
    sso_not_permitted: {
      badge: 'web.domains.sso.status_not_permitted_badge',
      hint: 'web.domains.sso.status_not_permitted_hint',
    },
    auth_disabled: {
      badge: 'web.domains.sso.status_auth_disabled_badge',
      hint: 'web.domains.sso.status_auth_disabled_hint',
    },
    unsupported_provider_type: {
      badge: 'web.domains.sso.status_unsupported_provider_badge',
      hint: 'web.domains.sso.status_unsupported_provider_hint',
    },
  };

  const ssoStatus = computed<{ tone: 'ok' | 'warn'; badge: string; hint: string } | null>(() => {
    if (!ssoConfigurable.value) return null;
    const verdict = props.tenantSso;
    if (!verdict) return null;
    if (verdict.available) {
      return {
        tone: 'ok',
        badge: t('web.domains.sso.status_active_badge'),
        hint: t('web.domains.sso.status_active_hint'),
      };
    }
    const copy = verdict.unavailable_reason
      ? UNAVAILABLE_REASON_COPY[verdict.unavailable_reason]
      : undefined;
    return {
      tone: 'warn',
      badge: t(copy?.badge ?? 'web.domains.sso.status_unavailable_badge'),
      hint: t(copy?.hint ?? 'web.domains.sso.status_unavailable_hint'),
    };
  });

  /**
   * Restricting to SSO requires confirmation when it would remain unavailable
   * after the atomic patch. `sso_not_permitted` can be caused solely by the
   * current SigninConfig having sso_enabled=false; selecting SSO fixes that in
   * the same PUT, so that one recoverable state is not a lockout. If SSO is
   * already enabled, the same verdict has another cause and remains guarded.
   * Absent verdict => false: no guard fires on a claim the server never made.
   */
  const ssoRestrictionRequiresConfirmation = computed(() => {
    const verdict = props.tenantSso;
    if (verdict?.available !== false) return false;
    return !(verdict.unavailable_reason === 'sso_not_permitted' && !props.formState.sso_enabled);
  });

  const METHOD_LABEL_KEYS: Record<SigninRestrictTo, string> = {
    password: 'web.domains.signin.method_password',
    email_auth: 'web.domains.signin.method_email_auth',
    webauthn: 'web.domains.signin.method_webauthn',
    sso: 'web.domains.signin.method_sso',
  };

  /**
   * Resolution notice for the two states the method picker cannot express
   * (ADR-034#resolution-is-model-owned / #resolution-intersects-never-widens),
   * rendered from the server's resolution verbatim:
   *
   * - `conflict` — this domain and the workspace-wide setting restrict to
   *   DIFFERENT methods, so neither applies and sign-in is closed. Named as a
   *   conflict rather than showing one side as if it had won; `restrict_to`
   *   carries the global method, the one still in force.
   * - `unavailable` — the restriction stands but its method cannot run here,
   *   so sign-in offers nothing. The method is still named ("SSO required,
   *   but unavailable here"), never blanked.
   */
  const restrictionNotice = computed<string | null>(() => {
    const resolution = props.effectiveRestrictTo;
    if (!resolution) return null;
    const method = resolution.restrict_to ? t(METHOD_LABEL_KEYS[resolution.restrict_to]) : null;
    if (resolution.source === 'conflict' && method) {
      return t('web.domains.signin.restriction_conflict_notice', { method });
    }
    if (resolution.state !== 'unavailable') return null;
    return method
      ? t('web.domains.signin.restriction_unavailable_notice', { method })
      : t('web.domains.signin.restriction_unavailable_unknown_notice');
  });

  interface MethodRow {
    value: SigninRestrictTo;
    label: string;
    /** Short descriptor shown in Mode B / as the method blurb. */
    blurb: string;
    /**
     * False when the method is listed for visibility but locked — currently
     * only SSO without the manage-SSO entitlement. Globally-unavailable
     * methods are omitted from the list entirely, never rendered locked.
     */
    available: boolean;
  }

  /** Methods selectable in "One specific method" mode (only globally-available ones). */
  const restrictMethods = computed<MethodRow[]>(() => {
    const rows: MethodRow[] = [
      {
        value: 'password',
        label: t('web.domains.signin.method_password'),
        blurb: t('web.domains.signin.method_password_blurb'),
        available: passwordAvailable,
      },
    ];
    if (emailAuthAvailable.value) {
      rows.push({
        value: 'email_auth',
        label: t('web.domains.signin.method_email_auth'),
        blurb: t('web.domains.signin.method_email_auth_blurb'),
        available: true,
      });
    }
    // Also listed — locked — when SSO is the CURRENT restriction. Omitting the
    // selected method would render a radiogroup with nothing checked, hiding
    // the domain's actual configuration; showing it locked reports the truth
    // and still refuses re-selection.
    if (ssoAvailable.value || props.formState.restrict_to === 'sso') {
      rows.push({
        value: 'sso',
        label: t('web.domains.signin.method_sso'),
        blurb: t('web.domains.signin.method_sso_blurb'),
        // Kept visible when unentitled (the lock badge is the upgrade prompt)
        // but not selectable: without the entitlement the org cannot configure
        // SSO credentials, so restrict_to=sso would dead-end the login page.
        available: ssoAvailable.value && props.canManageSso,
      });
    }
    // WebAuthn / Passkeys listed last — but NEVER offered for selection:
    // passkeys are host-scoped (rp_id = request.host), so a credential
    // registered on the canonical sign-in host can never authenticate on this
    // custom domain. Restricting a domain to webauthn-only is a guaranteed
    // dead end. The row appears (locked) ONLY when it is already the
    // persisted restriction — same keep-if-selected rationale as SSO above —
    // with a blurb naming the host-scope limitation instead of the pitch.
    if (props.formState.restrict_to === 'webauthn') {
      rows.push({
        value: 'webauthn',
        label: t('web.domains.signin.method_webauthn'),
        blurb: t('web.domains.signin.method_webauthn_unavailable'),
        available: false,
      });
    }
    return rows;
  });

  // ---------------------------------------------------------------------------
  // Local UI state
  // ---------------------------------------------------------------------------

  const showDeleteConfirm = ref(false);

  /**
   * The owner picked SSO as the only sign-in method while the server reports
   * tenant SSO unavailable here (#4111). Nothing is persisted until they
   * confirm; the radio stays unchecked because formState is untouched.
   */
  const pendingSsoRestriction = ref(false);

  const isEditing = computed(() => props.isConfigured);

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  /**
   * Switch to "Any available method": clears restrict_to (REPLACE → show all)
   * and re-enables sign-in when coming from "Sign-in disabled" — committed
   * atomically as one PUT.
   */
  const selectModeAny = () => {
    oneSelectedIntent.value = false;
    const patch: Partial<SigninConfigFormState> = {};
    if (props.formState.restrict_to !== null) patch.restrict_to = null;
    if (!props.formState.signin_enabled) patch.signin_enabled = true;
    if (Object.keys(patch).length === 0) {
      // Nothing changes value-wise; while following workspace defaults the
      // click still materializes the pin (ADR-024) — an empty patch saves the
      // seeded snapshot verbatim as an explicit override.
      if (!props.workspaceDefault) return;
      emit('auto-save', {}, 'restrict_to');
      return;
    }
    // Attribute the saving indicator to restrict_to only when it is actually
    // in the patch; a pure re-enable from "Sign-in disabled" (restrict_to
    // already null) saves signin_enabled alone.
    const fieldKey = 'restrict_to' in patch ? 'restrict_to' : 'signin_enabled';
    emit('auto-save', patch, fieldKey);
  };

  /**
   * Switch to "One specific method": reveal the picker locally but do NOT save
   * until a method is actually chosen (no method = nothing to persist). Coming
   * from "Sign-in disabled", re-enabling IS persisted immediately — sign-in
   * must come back on even before a method is picked (a preserved restrict_to
   * restores that method; null shows the picker).
   */
  const selectModeOne = () => {
    oneSelectedIntent.value = true;
    if (!props.formState.signin_enabled) {
      emit('auto-save', { signin_enabled: true }, 'signin_enabled');
    } else if (props.workspaceDefault && props.formState.restrict_to !== null) {
      // The inherited state already restricts to a method (seeded from the
      // global restrict_to), so this mode is pre-active and nothing changes
      // value-wise — but the click still materializes the pin (ADR-024) via
      // an empty patch. With restrict_to null nothing persists until a method
      // is actually picked.
      emit('auto-save', {}, 'restrict_to');
    }
  };

  /**
   * Switch to "Sign-in disabled": persists signin_enabled=false immediately.
   * While following workspace defaults, an inherited-disabled state still
   * saves on click — same value, but it materializes the pin (ADR-024).
   */
  const selectModeDisabled = () => {
    oneSelectedIntent.value = false;
    if (props.formState.signin_enabled || props.workspaceDefault) {
      emit('auto-save', { signin_enabled: false }, 'signin_enabled');
    }
  };

  /**
   * Pick a restrict_to method. Flips the method's availability flag on in the
   * same patch so the login page (which gates restrict_to through availability
   * resolution) can show it — committed atomically as one PUT.
   *
   * Other availability flags are intentionally left untouched: restrict_to
   * REPLACE semantics override them on the login page, and preserving them keeps
   * the user's Mode A settings intact for when they switch back.
   */
  const selectMethod = (value: SigninRestrictTo) => {
    // Disabled radios fire no events, but guard anyway: restricting to SSO
    // without BOTH tenant-SSO gates must be unexpressible — the SSO row is now
    // also rendered (locked) when it is the current restriction, so this is
    // the backstop for that row.
    if (value === 'sso' && !ssoConfigurable.value) return;
    // WebAuthn is never (re)selectable: passkeys are host-scoped (rp_id), so
    // a webauthn-only restriction dead-ends sign-in on a custom domain. Its
    // row only renders locked (keep-if-selected); this backstop also keeps
    // onMethodClick's ADR-024 materialize-on-touch path from saving it.
    if (value === 'webauthn') return;
    // Restricting to SSO the server says cannot run here fails CLOSED
    // (ADR-034#resolution-intersects-never-widens): the sign-in page goes
    // dark for everyone. Confirm BEFORE
    // the PUT — this form auto-saves, so a post-hoc notice would arrive after
    // the lockout. Nothing persists until confirmSsoRestriction runs.
    if (value === 'sso' && ssoRestrictionRequiresConfirmation.value) {
      pendingSsoRestriction.value = true;
      return;
    }
    commitMethod(value);
  };

  /** Persist a restrict_to choice. Guards live in selectMethod. */
  const commitMethod = (value: SigninRestrictTo) => {
    const patch: Partial<SigninConfigFormState> = { restrict_to: value };
    if (value === 'email_auth') patch.email_auth_enabled = true;
    if (value === 'sso') patch.sso_enabled = true;
    if (!props.formState.signin_enabled) patch.signin_enabled = true;
    emit('auto-save', patch, 'restrict_to');
  };

  /** Save the SSO-only restriction the operator was warned about (#4111). */
  const confirmSsoRestriction = () => {
    pendingSsoRestriction.value = false;
    commitMethod('sso');
  };

  const cancelSsoRestriction = () => {
    pendingSsoRestriction.value = false;
  };

  /**
   * An already-checked radio fires no `change` event on click. While following
   * workspace defaults the seeded method can be pre-checked, and clicking it
   * must still materialize the pin (ADR-024) — so route that one case through
   * selectMethod from `click`. Unchecked radios fall through to `change`
   * (restrict_to differs at click time), so nothing double-saves.
   */
  const onMethodClick = (value: SigninRestrictTo) => {
    if (props.isSaving) return;
    if (props.workspaceDefault && props.formState.restrict_to === value) {
      selectMethod(value);
    }
  };

  const handleDelete = () => {
    if (props.isDeleting) return;
    emit('delete');
    showDeleteConfirm.value = false;
  };
</script>

<template>
  <div class="space-y-6">
    <!-- Loading State -->
    <SettingsSkeleton
      v-if="isLoading"
      :heading="false" />

    <div
      v-else
      class="space-y-6">
      <!-- Mode switch -->
      <fieldset>
        <legend
          id="signin-mode-legend"
          class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signin.mode_question') }}
        </legend>

        <div
          class="mt-3 inline-flex rounded-lg border border-gray-300 bg-gray-100 p-1 dark:border-gray-600 dark:bg-gray-700"
          role="radiogroup"
          aria-labelledby="signin-mode-legend"
          @keydown="onModeKeydown">
          <!-- DOM order: Sign-in disabled is rendered first, then Any available
               method (the actual default), then One specific method
               (withheld only when showRestrictMode is off). -->
          <button
            id="signin-mode-disabled"
            type="button"
            role="radio"
            :aria-checked="isModeDisabled"
            :tabindex="modeTabindex(0)"
            :disabled="isSaving"
            @click="selectModeDisabled"
            :class="[
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500',
              isModeDisabled
                ? 'bg-white text-gray-900 shadow-sm dark:bg-gray-800 dark:text-white'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200',
            ]">
            {{ t('web.domains.signin.mode_disabled') }}
          </button>
          <button
            id="signin-mode-any"
            type="button"
            role="radio"
            :aria-checked="isModeAny"
            :tabindex="modeTabindex(1)"
            :disabled="isSaving"
            @click="selectModeAny"
            :class="[
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500',
              isModeAny
                ? 'bg-white text-gray-900 shadow-sm dark:bg-gray-800 dark:text-white'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200',
            ]">
            {{ t('web.domains.signin.mode_any') }}
          </button>
          <button
            v-if="showRestrictMode"
            id="signin-mode-one"
            type="button"
            role="radio"
            :aria-checked="isModeOne"
            :tabindex="modeTabindex(2)"
            :disabled="isSaving"
            @click="selectModeOne"
            :class="[
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500',
              isModeOne
                ? 'bg-white text-gray-900 shadow-sm dark:bg-gray-800 dark:text-white'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200',
            ]">
            {{ t('web.domains.signin.mode_one') }}
          </button>
          <!-- When Mode B ("One specific method") is the active mode but its
               interactive segment is withheld (showRestrictMode=false), expose
               an sr-only, non-interactive radio so the radiogroup reports its
               true selection to assistive tech. Without it, both visible radios
               read aria-checked=false and AT announces a radiogroup with no
               selection (WCAG 2.1 SC 4.1.2 Name, Role, Value). aria-disabled +
               tabindex=-1 keep it out of the tab order and prevent switching
               INTO the withheld mode; the visible segments stay keyboard-
               reachable and can still switch to disabled/any. -->
          <span
            v-if="isModeOne && !showRestrictMode"
            id="signin-mode-one-active"
            role="radio"
            aria-checked="true"
            aria-disabled="true"
            tabindex="-1"
            class="sr-only">
            {{ t('web.domains.signin.mode_one') }}
          </span>
        </div>

        <p
          id="signin-mode-hint"
          class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ modeHint }}
        </p>

        <!-- Resolved-restriction notice
             (ADR-034#resolution-is-model-owned / #resolution-intersects-never-widens):
             the restriction stands but nothing can satisfy it, so sign-in is closed here.
             Server-resolved, rendered verbatim. role="status" announces it;
             the icon is decorative and the text carries the meaning. -->
        <div
          v-if="restrictionNotice"
          data-testid="signin-restriction-notice"
          role="status"
          class="mt-3 flex items-start gap-3 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            class="mt-0.5 size-5 flex-shrink-0 text-amber-600 dark:text-amber-400"
            aria-hidden="true" />
          <p class="flex-1 text-sm text-amber-700 dark:text-amber-300">
            {{ restrictionNotice }}
          </p>
        </div>
      </fieldset>

      <!-- ===================================================================
           Mode: Sign-in disabled — no method list; explain what visitors see
           =================================================================== -->
      <div
        v-if="isModeDisabled"
        data-testid="signin-disabled-mode-notice"
        class="flex items-start gap-3 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20">
        <OIcon
          collection="heroicons"
          name="information-circle"
          class="mt-0.5 size-5 flex-shrink-0 text-amber-500 dark:text-amber-400"
          aria-hidden="true" />
        <p class="flex-1 text-sm text-amber-700 dark:text-amber-300">
          {{ t('web.domains.signin.mode_disabled_notice') }}
        </p>
      </div>

      <!-- ===================================================================
           Mode A — Any available method: static rows + availability toggles
           =================================================================== -->
      <fieldset
        v-else-if="!isModeOne"
        class="space-y-3">
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signin.methods_list_label') }}
        </legend>

        <!-- Password (static, always available) -->
        <div
          class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.domains.signin.method_password') }}
            </p>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.domains.signin.availability_always') }}
            </p>
          </div>
        </div>

        <!-- Email / magic link (availability toggle, gated on global) -->
        <div
          class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.domains.signin.method_email_auth') }}
            </p>
            <p
              id="signin-email-auth-hint"
              class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{
                emailAuthAvailable
                  ? t('web.domains.signin.allow_on_domain')
                  : t('web.domains.signin.availability_unavailable')
              }}
            </p>
          </div>
          <ToggleWithIcon
            :enabled="Boolean(formState.email_auth_enabled) && emailAuthAvailable"
            :disabled="isSaving || !emailAuthAvailable"
            :loading="savingField === 'email_auth_enabled'"
            :on-label="t('web.COMMON.enabled')"
            :off-label="t('web.COMMON.disabled')"
            @update:enabled="
              emit('auto-save', { email_auth_enabled: $event }, 'email_auth_enabled')
            " />
        </div>

        <!-- Single Sign-On (Configure + availability toggle, gated on global) -->
        <div
          class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-gray-900 dark:text-white">
                {{ t('web.domains.signin.method_sso') }}
              </p>
              <p
                id="signin-sso-hint"
                class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{
                  ssoAvailable
                    ? t('web.domains.signin.allow_on_domain')
                    : t('web.domains.signin.availability_unavailable')
                }}
              </p>
            </div>
            <div class="flex items-center gap-3">
              <button
                v-if="ssoConfigurable"
                type="button"
                @click="emit('configure-sso')"
                class="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
                <OIcon
                  collection="heroicons"
                  name="cog-6-tooth"
                  class="size-4"
                  aria-hidden="true" />
                {{
                  ssoConfigured
                    ? t('web.domains.sso.edit_credentials')
                    : t('web.domains.sso.configure_button')
                }}
              </button>
              <!-- Upgrade lock is for the ENTITLEMENT only. When the blocker is
                 the install flag instead, neither control renders here — the
                 hint above already reads "Unavailable", and "Upgrade to
                 configure" would name the wrong cause (no plan unlocks an
                 operator's ORGS_SSO_ENABLED). -->
              <span
                v-else-if="!canManageSso"
                class="inline-flex items-center gap-1.5 text-sm text-gray-400 dark:text-gray-500">
                <OIcon
                  collection="heroicons"
                  name="lock-closed"
                  class="size-4"
                  aria-hidden="true" />
                {{ t('web.domains.sso.upgrade_required') }}
              </span>
              <!-- Locked without the manage-SSO entitlement (or with tenant SSO
                 off install-wide): the org cannot configure SSO credentials, so
                 the method can never activate — showing an operable toggle next
                 to the upgrade lock would contradict it. `:enabled` reports the
                 STORED value alone: the runtime ladder
                 (SsoConfig.tenant_sso_unavailable_reason) gates on the SsoConfig
                 record and sso_permitted_for?, never on these two management
                 gates, so ANDing them in here would render OFF for a domain
                 whose tenant SSO is actually live. -->
              <ToggleWithIcon
                :enabled="Boolean(formState.sso_enabled)"
                :disabled="isSaving || !ssoAvailable || !canManageSso"
                :loading="savingField === 'sso_enabled'"
                :on-label="t('web.COMMON.enabled')"
                :off-label="t('web.COMMON.disabled')"
                @update:enabled="emit('auto-save', { sso_enabled: $event }, 'sso_enabled')" />
            </div>
          </div>

          <!-- Tenant-SSO status line (#4111): the server's single verdict on
               whether SSO can be offered here, and which rung blocks it when
               it can't. Rendered verbatim — no client-side derivation
               (ADR-024). role="status" so the reason is announced, and the
               badge carries text (not colour alone) for WCAG 1.4.1. Fixed
               semantic hues per #4132: amber = warning, green = success. -->
          <div
            v-if="ssoStatus"
            data-testid="sso-tenant-status"
            role="status"
            class="mt-3 flex items-start gap-2">
            <span
              :class="[
                'inline-flex flex-shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
                ssoStatus.tone === 'ok'
                  ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300'
                  : 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300',
              ]">
              <OIcon
                collection="heroicons"
                :name="ssoStatus.tone === 'ok' ? 'check-circle' : 'exclamation-triangle'"
                class="size-3.5"
                aria-hidden="true" />
              {{ ssoStatus.badge }}
            </span>
            <span
              :class="[
                'text-sm',
                ssoStatus.tone === 'ok'
                  ? 'text-green-700 dark:text-green-300'
                  : 'text-amber-700 dark:text-amber-300',
              ]">
              {{ ssoStatus.hint }}
            </span>
          </div>
        </div>

        <!-- Passkeys / WebAuthn (static, follows global policy) — listed last -->
        <div
          :class="[
            'flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50',
            webauthnAvailable ? '' : 'opacity-60',
          ]">
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.domains.signin.method_webauthn') }}
            </p>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{
                webauthnAvailable
                  ? t('web.domains.signin.availability_global_on')
                  : t('web.domains.signin.availability_global_off')
              }}
            </p>
          </div>
        </div>
      </fieldset>

      <!-- ===================================================================
           Mode B — One specific method: single-choice radio list, no toggles
           =================================================================== -->
      <fieldset
        v-else
        class="space-y-3">
        <legend
          id="signin-restrict-legend"
          class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signin.methods_list_label') }}
        </legend>
        <p
          id="signin-restrict-hint"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signin.restrict_picker_hint') }}
        </p>

        <div
          class="space-y-3"
          role="radiogroup"
          aria-labelledby="signin-restrict-legend"
          aria-describedby="signin-restrict-hint">
          <label
            v-for="method in restrictMethods"
            :key="method.value"
            :class="[
              'relative flex items-center justify-between rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              method.available ? 'cursor-pointer' : 'cursor-not-allowed opacity-60',
              formState.restrict_to === method.value
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : method.available
                  ? 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500'
                  : 'border-gray-300 bg-white dark:border-gray-600 dark:bg-gray-700',
            ]">
            <span class="flex items-start gap-3">
              <input
                type="radio"
                :id="`signin-restrict-${method.value}`"
                name="restrict_to"
                :value="method.value"
                :checked="formState.restrict_to === method.value"
                :disabled="isSaving || !method.available"
                @change="selectMethod(method.value)"
                @click="onMethodClick(method.value)"
                class="mt-0.5 size-4 border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600"
                :aria-describedby="`signin-restrict-${method.value}-description`" />
              <span class="flex flex-1 flex-col">
                <span
                  :class="[
                    'block text-sm font-medium',
                    formState.restrict_to === method.value
                      ? 'text-brand-900 dark:text-brand-100'
                      : 'text-gray-900 dark:text-white',
                  ]">
                  {{ method.label }}
                </span>
                <span
                  :id="`signin-restrict-${method.value}-description`"
                  class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                  {{ method.blurb }}
                </span>
                <!-- Compact tenant-SSO status — see the Mode A row for
                     rationale (#4111, ADR-024). The reason is rendered as
                     text, not only as a title tooltip: a tooltip is neither
                     keyboard- nor screen-reader-reliable. -->
                <span
                  v-if="method.value === 'sso' && ssoStatus"
                  data-testid="sso-tenant-status-compact"
                  role="status"
                  class="mt-1.5 flex flex-col items-start gap-1">
                  <span
                    :class="[
                      'inline-flex w-fit items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
                      ssoStatus.tone === 'ok'
                        ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300'
                        : 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300',
                    ]">
                    <OIcon
                      collection="heroicons"
                      :name="ssoStatus.tone === 'ok' ? 'check-circle' : 'exclamation-triangle'"
                      class="size-3.5"
                      aria-hidden="true" />
                    {{ ssoStatus.badge }}
                  </span>
                  <span
                    :class="[
                      'text-xs',
                      ssoStatus.tone === 'ok'
                        ? 'text-green-700 dark:text-green-300'
                        : 'text-amber-700 dark:text-amber-300',
                    ]">
                    {{ ssoStatus.hint }}
                  </span>
                </span>
              </span>
            </span>

            <!-- SSO Configure stays reachable in Mode B — same gates as Mode A:
                 the button needs BOTH write-endpoint gates (ssoConfigurable),
                 and the upgrade lock names the ENTITLEMENT only. When the
                 blocker is the install flag, neither renders — no plan unlocks
                 an operator's ORGS_SSO_ENABLED. -->
            <span
              v-if="method.value === 'sso'"
              class="ml-3 flex-shrink-0">
              <button
                v-if="ssoConfigurable"
                type="button"
                @click.prevent="emit('configure-sso')"
                class="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
                <OIcon
                  collection="heroicons"
                  name="cog-6-tooth"
                  class="size-4"
                  aria-hidden="true" />
                {{
                  ssoConfigured
                    ? t('web.domains.sso.edit_credentials')
                    : t('web.domains.sso.configure_button')
                }}
              </button>
              <span
                v-else-if="!canManageSso"
                class="inline-flex items-center gap-1.5 text-sm text-gray-400 dark:text-gray-500">
                <OIcon
                  collection="heroicons"
                  name="lock-closed"
                  class="size-4"
                  aria-hidden="true" />
                {{ t('web.domains.sso.upgrade_required') }}
              </span>
            </span>
          </label>
        </div>

        <!-- SSO-restriction lockout guard (#4111). Restricting to a method the
             server says cannot run here fails CLOSED
             (ADR-034#resolution-intersects-never-widens), so the
             sign-in page would go dark for everyone. The form auto-saves, so
             the warning has to land BEFORE the PUT: nothing is persisted until
             "Restrict anyway". role="alert" announces it immediately, and the
             colour is redundant with the text (WCAG 1.4.1). -->
        <div
          v-if="pendingSsoRestriction"
          data-testid="sso-restriction-lockout-warning"
          role="alert"
          class="flex flex-col gap-3 rounded-md bg-amber-50 px-4 py-3 sm:flex-row sm:items-start sm:justify-between dark:bg-amber-900/20">
          <div class="flex items-start gap-3">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              class="mt-0.5 size-5 flex-shrink-0 text-amber-600 dark:text-amber-400"
              aria-hidden="true" />
            <div class="text-sm">
              <p class="font-medium text-amber-800 dark:text-amber-200">
                {{ t('web.domains.signin.sso_restrict_warning_title') }}
              </p>
              <p class="mt-1 text-amber-700 dark:text-amber-300">
                {{ t('web.domains.signin.sso_restrict_warning_body') }}
              </p>
            </div>
          </div>
          <div class="flex flex-shrink-0 items-center gap-2">
            <button
              type="button"
              data-testid="sso-restriction-lockout-confirm"
              :disabled="isSaving"
              @click="confirmSsoRestriction"
              class="inline-flex items-center rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-amber-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-500 dark:hover:bg-amber-400">
              {{ t('web.domains.signin.sso_restrict_warning_confirm') }}
            </button>
            <button
              type="button"
              data-testid="sso-restriction-lockout-cancel"
              @click="cancelSsoRestriction"
              class="inline-flex items-center rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
              {{ t('web.COMMON.word_cancel') }}
            </button>
          </div>
        </div>
      </fieldset>

      <!-- Reset to defaults (two-step) -->
      <!-- Internally a DELETE of this domain's SigninConfig record; to the user
           it reverts sign-in to the global defaults. The SsoConfig (credentials)
           is a separate record and is NOT touched here — it is managed on the
           SSO configuration screen. -->
      <div
        v-if="isEditing"
        class="border-t border-gray-200 pt-6 dark:border-gray-700">
        <template v-if="!showDeleteConfirm">
          <button
            type="button"
            @click="showDeleteConfirm = true"
            :disabled="isDeleting || isSaving"
            class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            <OIcon
              collection="heroicons"
              name="arrow-uturn-left"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.domains.signin.reset_to_defaults') }}
          </button>
        </template>

        <div
          v-else
          class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div class="text-sm">
            <p class="font-medium text-gray-900 dark:text-white">
              {{ t('web.domains.signin.reset_confirm') }}
            </p>
            <p class="mt-1 text-gray-500 dark:text-gray-400">
              {{ t('web.domains.signin.reset_keeps_sso') }}
            </p>
          </div>
          <div class="flex flex-shrink-0 items-center gap-2">
            <button
              type="button"
              @click="handleDelete"
              :disabled="isDeleting"
              class="inline-flex items-center rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-amber-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-500 dark:hover:bg-amber-400">
              {{ isDeleting ? t('web.COMMON.processing') : t('web.domains.signin.reset_action') }}
            </button>
            <button
              type="button"
              @click="showDeleteConfirm = false"
              :disabled="isDeleting"
              class="inline-flex items-center rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
              {{ t('web.COMMON.word_cancel') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
