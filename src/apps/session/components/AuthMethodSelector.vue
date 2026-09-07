<!-- src/apps/session/components/AuthMethodSelector.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { getBootstrapValue } from '@/services/bootstrap.service';
  import {
    isMagicLinksEnabled,
    isSsoEnabled,
    isWebAuthnEnabled,
    getSsoProviders,
    getRestrictTo,
    isSsoOnlyMode,
    isSsoEnforcedForDomain,
  } from '@/utils/features';
  import { ref, computed } from 'vue';
  import { storeToRefs } from 'pinia';

  import PasswordlessFirstSignIn from './PasswordlessFirstSignIn.vue';
  import SignInForm from './SignInForm.vue';
  import SsoButton from './SsoButton.vue';

  const { t } = useI18n();

  export interface Props {
    locale?: string;
    /**
     * Preselect a specific auth tab on first render (contextual default, not a
     * persisted user choice). Forwarded to the passwordless-first tab UI. Used to
     * land on "password" when the user returns right after email verification.
     */
    initialMode?: 'passkey' | 'passwordless' | 'password';
  }

  withDefaults(defineProps<Props>(), {
    locale: 'en',
    initialMode: undefined,
  });

  type AuthMode = 'passwordless' | 'passkey' | 'password';

  const emit = defineEmits<{
    (e: 'mode-change', mode: AuthMode): void;
    /** Forwarded from PasswordlessFirstSignIn — see its `link-sent` docs. */
    (e: 'link-sent'): void;
  }>();

  // Custom domains force SSO-only authentication
  const { isCustom } = storeToRefs(useProductIdentity());

  // Check which methods are enabled
  const magicLinksEnabled = isMagicLinksEnabled();
  const webauthnEnabled = isWebAuthnEnabled();
  const ssoEnabled = isSsoEnabled();
  const ssoOnly = computed(() => isSsoOnlyMode());

  // Extract SSO providers via feature utility
  const ssoProviders = computed(() => getSsoProviders());

  // SSO enforcement for custom domains
  const enforceSsoForDomain = computed(() => isSsoEnforcedForDomain());

  // SSO is required when either the global sso_only flag is on, or the
  // active custom domain has enforce_sso_only enabled.
  const ssoRequired = computed(
    () => ssoOnly.value || (isCustom.value && enforceSsoForDomain.value)
  );

  // SSO is usable when it's globally enabled and at least one provider is configured.
  const ssoConfigured = computed(() => ssoEnabled && ssoProviders.value.length > 0);

  // SSO-only mode: show only SSO buttons when SSO is both required and configured.
  const showSsoOnly = computed(() => ssoRequired.value && ssoConfigured.value);

  // Custom domain that requires SSO but has no working provider: show a
  // friendly "SSO required" message instead of standard auth forms. The
  // requirement can come from either axis — the domain's enforce_sso_only
  // flag (SsoConfig) or restrict_to='sso' (SigninConfig, resolved into
  // features.restrict_to by the backend) — and in both cases falling through
  // to the password/email forms would advertise methods the domain owner
  // chose to hide (and, for restrict_to, whose credentials may be dormant).
  // Canonical requests never reach this branch: a global restrict_to='sso'
  // with no provider configured is a fatal boot error, not a restriction the
  // backend quietly drops (ADR-034#degradation-is-fail-closed), so the
  // combination only arises on custom domains.
  const showCustomDomainNoSso = computed(
    () => isCustom.value && ssoRequired.value && !ssoConfigured.value
  );

  // Single-method restriction. TWO fields carry it, both resolved domain-aware
  // by the backend serializer (ConfigSerializer#build_feature_flags):
  //
  //   features.restrict_to           Legacy scalar projection: the method name,
  //                                  or null. Deliberately nulled when the
  //                                  resolution is `unavailable`, so it cannot
  //                                  express "restricted but unsatisfiable".
  //                                  That null-on-unavailable is kept for
  //                                  backwards compatibility — consumers
  //                                  predating the resolver read only this key
  //                                  and understand string-or-null alone.
  //   features.effective_restrict_to The resolver's own wire form,
  //                                  { state, restrict_to, source }
  //                                  (effectiveRestrictToSchema in
  //                                  @/schemas/contracts/bootstrap.ts). It
  //                                  preserves state: 'unavailable'.
  //
  // Display code must fail closed on effective_restrict_to, NOT on the scalar:
  // the nulled scalar reads as "no restriction", which would widen an
  // unsatisfiable restriction back into standard mode and re-offer every
  // method the restriction hid. signInUnavailable is that check, and its
  // template branch precedes every auth form.
  //
  // restrictedMethod then handles the satisfiable narrowing: 'sso' is carried
  // by ssoRequired/showSsoOnly above; the other three values narrow the
  // rendering below to that one method. It returns null when the named method's
  // own feature flag is off, which falls through to the standard multi-method
  // UI — safe only because the `unavailable` state was already intercepted
  // above, never as a substitute for that check.
  const restrictTo = getRestrictTo();
  const signInUnavailable = computed(
    () => getBootstrapValue('features')?.effective_restrict_to?.state === 'unavailable'
  );
  const restrictedMethod = computed<'password' | 'email_auth' | 'webauthn' | null>(() => {
    if (restrictTo === 'password') return 'password';
    if (restrictTo === 'email_auth' && magicLinksEnabled) return 'email_auth';
    if (restrictTo === 'webauthn' && webauthnEnabled) return 'webauthn';
    return null;
  });

  // Show passwordless-first UI when any passwordless method is enabled
  const hasPasswordlessMethods = computed(() => magicLinksEnabled || webauthnEnabled);

  // Track current mode for footer context (emitted from PasswordlessFirstSignIn)
  const currentMode = ref<AuthMode>('passwordless');

  const handleModeChange = (mode: AuthMode) => {
    currentMode.value = mode;
    emit('mode-change', mode);
  };

  // Expose current mode for parent component (Login.vue) to use for footer
  defineExpose({ currentMode });
</script>

<template>
  <div
    class="space-y-6"
    data-testid="auth-standard-section">
    <!-- A restriction stands but no method can satisfy it. This branch must
         precede every auth form so display behavior matches the runtime gate. -->
    <template v-if="signInUnavailable">
      <div
        role="alert"
        class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800/50"
        data-testid="auth-signin-unavailable">
        <p class="text-sm font-medium text-gray-900 dark:text-white/90">
          {{ t('web.organizations.invitations.signin_unavailable_title') }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.signin_unavailable_unknown_body') }}
        </p>
      </div>
    </template>

    <!-- Custom domain without SSO: friendly availability message -->
    <template v-else-if="showCustomDomainNoSso">
      <div
        role="note"
        class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800/50"
        data-testid="auth-custom-domain-no-sso">
        <p class="text-sm font-medium text-gray-900 dark:text-white/90">
          {{ t('web.login.custom_domain_sso_title') }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.login.custom_domain_sso_description') }}
        </p>
      </div>
    </template>

    <!-- SSO-only mode: render only SSO provider buttons -->
    <template v-else-if="showSsoOnly">
      <div
        class="space-y-3"
        data-testid="auth-sso-only-section">
        <SsoButton
          v-for="provider in ssoProviders"
          :key="provider.route_name"
          :route-name="provider.route_name"
          :display-name="provider.display_name" />
      </div>
    </template>

    <!-- Single-method restriction: password only (no tabs, no SSO section) -->
    <template v-else-if="restrictedMethod === 'password'">
      <SignInForm :locale="locale" />
    </template>

    <!-- Single-method restriction: one passwordless method, password tab and
         SSO section withheld -->
    <template v-else-if="restrictedMethod === 'email_auth' || restrictedMethod === 'webauthn'">
      <PasswordlessFirstSignIn
        :locale="locale"
        :initial-mode="initialMode"
        :magic-links-enabled="restrictedMethod === 'email_auth'"
        :webauthn-enabled="restrictedMethod === 'webauthn'"
        :password-enabled="false"
        @mode-change="handleModeChange"
        @link-sent="emit('link-sent')" />
    </template>

    <!-- Standard auth mode: password/passwordless forms with optional SSO -->
    <template v-else>
      <!-- Passwordless-first mode when any passwordless method is enabled -->
      <PasswordlessFirstSignIn
        v-if="hasPasswordlessMethods"
        :locale="locale"
        :initial-mode="initialMode"
        :magic-links-enabled="magicLinksEnabled"
        :webauthn-enabled="webauthnEnabled"
        @mode-change="handleModeChange"
        @link-sent="emit('link-sent')" />

      <!-- Password-only mode when no passwordless methods enabled -->
      <SignInForm
        v-else
        :locale="locale" />

      <!-- SSO section when SSO is enabled -->
      <template v-if="ssoConfigured">
        <!-- Divider -->
        <div
          class="relative"
          data-testid="auth-sso-divider">
          <div
            class="absolute inset-0 flex items-center"
            aria-hidden="true">
            <div class="w-full border-t border-gray-300 dark:border-gray-600"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="bg-white px-2 text-gray-500 dark:bg-gray-800 dark:text-gray-400">
              {{ t('web.login.or_continue_with') }}
            </span>
          </div>
        </div>

        <!-- SSO Buttons — one per configured provider -->
        <div class="space-y-3">
          <SsoButton
            v-for="provider in ssoProviders"
            :key="provider.route_name"
            :route-name="provider.route_name"
            :display-name="provider.display_name" />
        </div>
      </template>
    </template>
  </div>
</template>
