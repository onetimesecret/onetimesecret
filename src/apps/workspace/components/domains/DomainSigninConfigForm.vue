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
 * login page.
 *
 * Everything auto-saves (PUT is full-replacement); there is no Save button.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import type { SigninRestrictTo } from '@/schemas/shapes/domains/signin-config';
import type { SigninConfigFormState } from '@/shared/composables/useSigninConfig';

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
  ssoConfigured: boolean;
  canManageSso: boolean;
  /**
   * Globally-available auth methods (install/global config). Gates which
   * methods are offered: a method that is off site-wide must never be
   * selectable, or restrict_to/availability would produce a blank login page.
   * Password and WebAuthn have no per-domain field; only the global flag gates
   * them. undefined upstream is treated as available (codebase convention).
   */
  globalAvailability: { email_auth: boolean; webauthn: boolean; sso: boolean };
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
const MODE_SEGMENT_IDS = ['signin-mode-any', 'signin-mode-one', 'signin-mode-disabled'] as const;

const checkedModeIndex = computed(() => {
  if (isModeDisabled.value) return 2;
  if (isModeOne.value) return 1;
  return 0;
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
  }
);

// ---------------------------------------------------------------------------
// Method availability (only offer globally-available methods)
// ---------------------------------------------------------------------------

const passwordAvailable = true; // always available
const webauthnAvailable = computed(() => props.globalAvailability.webauthn);
const emailAuthAvailable = computed(() => props.globalAvailability.email_auth);
const ssoAvailable = computed(() => props.globalAvailability.sso);

interface MethodRow {
  value: SigninRestrictTo;
  label: string;
  /** Short descriptor shown in Mode B / as the method blurb. */
  blurb: string;
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
  if (ssoAvailable.value) {
    rows.push({
      value: 'sso',
      label: t('web.domains.signin.method_sso'),
      blurb: t('web.domains.signin.method_sso_blurb'),
      available: true,
    });
  }
  // WebAuthn / Passkeys listed last.
  if (webauthnAvailable.value) {
    rows.push({
      value: 'webauthn',
      label: t('web.domains.signin.method_webauthn'),
      blurb: t('web.domains.signin.method_webauthn_blurb'),
      available: true,
    });
  }
  return rows;
});

// ---------------------------------------------------------------------------
// Local UI state
// ---------------------------------------------------------------------------

const showDeleteConfirm = ref(false);

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
  if (Object.keys(patch).length === 0) return;
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
  }
};

/** Switch to "Sign-in disabled": persists signin_enabled=false immediately. */
const selectModeDisabled = () => {
  oneSelectedIntent.value = false;
  if (props.formState.signin_enabled) {
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
  const patch: Partial<SigninConfigFormState> = { restrict_to: value };
  if (value === 'email_auth') patch.email_auth_enabled = true;
  if (value === 'sso') patch.sso_enabled = true;
  if (!props.formState.signin_enabled) patch.signin_enabled = true;
  emit('auto-save', patch, 'restrict_to');
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

    <div v-else class="space-y-6">
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
          <button
            id="signin-mode-any"
            type="button"
            role="radio"
            :aria-checked="isModeAny"
            :tabindex="modeTabindex(0)"
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
            id="signin-mode-one"
            type="button"
            role="radio"
            :aria-checked="isModeOne"
            :tabindex="modeTabindex(1)"
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
          <button
            id="signin-mode-disabled"
            type="button"
            role="radio"
            :aria-checked="isModeDisabled"
            :tabindex="modeTabindex(2)"
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
        </div>

        <p
          id="signin-mode-hint"
          class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ modeHint }}
        </p>
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
      <fieldset v-else-if="!isModeOne" class="space-y-3">
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signin.methods_list_label') }}
        </legend>

        <!-- Password (static, always available) -->
        <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
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
        <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
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
            @update:enabled="emit('auto-save', { email_auth_enabled: $event }, 'email_auth_enabled')" />
        </div>

        <!-- Single Sign-On (Configure + availability toggle, gated on global) -->
        <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
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
              v-if="canManageSso"
              type="button"
              @click="emit('configure-sso')"
              class="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
              <OIcon
                collection="heroicons"
                name="cog-6-tooth"
                class="size-4"
                aria-hidden="true" />
              {{ ssoConfigured ? t('web.domains.sso.edit_credentials') : t('web.domains.sso.configure_button') }}
            </button>
            <span
              v-else
              class="inline-flex items-center gap-1.5 text-sm text-gray-400 dark:text-gray-500">
              <OIcon
                collection="heroicons"
                name="lock-closed"
                class="size-4"
                aria-hidden="true" />
              {{ t('web.domains.sso.upgrade_required') }}
            </span>
            <ToggleWithIcon
              :enabled="Boolean(formState.sso_enabled) && ssoAvailable"
              :disabled="isSaving || !ssoAvailable"
              :loading="savingField === 'sso_enabled'"
              :on-label="t('web.COMMON.enabled')"
              :off-label="t('web.COMMON.disabled')"
              @update:enabled="emit('auto-save', { sso_enabled: $event }, 'sso_enabled')" />
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
      <fieldset v-else class="space-y-3">
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
              'relative flex cursor-pointer items-center justify-between rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              formState.restrict_to === method.value
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500',
            ]">
            <span class="flex items-start gap-3">
              <input
                type="radio"
                :id="`signin-restrict-${method.value}`"
                name="restrict_to"
                :value="method.value"
                :checked="formState.restrict_to === method.value"
                :disabled="isSaving"
                @change="selectMethod(method.value)"
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
              </span>
            </span>

            <!-- SSO Configure stays reachable in Mode B -->
            <span v-if="method.value === 'sso'" class="ml-3 flex-shrink-0">
              <button
                v-if="canManageSso"
                type="button"
                @click.prevent="emit('configure-sso')"
                class="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
                <OIcon
                  collection="heroicons"
                  name="cog-6-tooth"
                  class="size-4"
                  aria-hidden="true" />
                {{ ssoConfigured ? t('web.domains.sso.edit_credentials') : t('web.domains.sso.configure_button') }}
              </button>
              <span
                v-else
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
            class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            <OIcon
              collection="heroicons"
              name="arrow-uturn-left"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.domains.signin.reset_to_defaults') }}
          </button>
        </template>

        <div v-else class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
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
              class="inline-flex items-center rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
              {{ t('web.COMMON.word_cancel') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
