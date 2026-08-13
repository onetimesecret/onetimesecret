<!-- src/apps/session/views/AcceptInvite.vue -->

<script setup lang="ts">
  import InviteSignInForm from '@/apps/session/components/InviteSignInForm.vue';
  import InviteSignUpForm from '@/apps/session/components/InviteSignUpForm.vue';
  import SsoButton from '@/apps/session/components/SsoButton.vue';
  import {
    showInviteResponseSchema,
    type AuthMethod,
    type ShowInviteResponse,
  } from '@/schemas/api/invite/responses/show-invite';
  import type { SigninRestrictTo } from '@/schemas/contracts/custom-domain/signin-config';
  import { classifyError } from '@/schemas/errors';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
  import { useAuth } from '@/shared/composables/useAuth';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useCsrfStore } from '@/shared/stores/csrfStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { formatDisplayDate } from '@/utils/format';
  import { onMounted, ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute, useRouter } from 'vue-router';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const csrfStore = useCsrfStore();
  const organizationStore = useOrganizationStore();
  const { logout } = useAuth();
  const $api = useApi();

  const { wrap } = useAsyncHandler({
    notify: false,
  });

  // Delay for the direct accept/decline paths where the server has
  // already confirmed and no background auth sync is pending.
  const DIRECT_ACTION_REDIRECT_DELAY_MS = 2000;

  const invitationToken = ref<string>(route.params.token as string);
  const invitation = ref<ShowInviteResponse | null>(null);

  const isLoading = ref(true);
  const error = ref('');
  const success = ref('');
  const isProcessing = ref(false);

  /**
   * Invite state machine
   *
   * States:
   * - loading: Initial fetch in progress
   * - signup_required: Unauthenticated default (the API deliberately does not
   *   reveal whether an account exists — see show-invite schema note)
   * - signin_required: Unauthenticated, signup reported unavailable for this
   *   invitation (generic signup_unavailable error, #3856) — signin is the
   *   fallback path
   * - direct_accept: Authenticated with correct email, can accept immediately
   * - wrong_email: Authenticated but with different email than invitation
   * - already_accepted: Invitation was already accepted (status: active)
   * - accepted: User just accepted in this session (terminal, redirect pending)
   * - declined: User just declined in this session (terminal, redirect pending)
   * - invalid: Invitation is expired, declined, revoked, or doesn't exist
   * - restricted_host: This host restricts sign-in to a method that is not
   *   password (ADR-034#invite-signup-is-gated), so the signup form here
   *   would 404. Offers the
   *   host's actual method instead.
   * - signin_unavailable: The host's restriction cannot be honoured at all
   *   (resolution `unavailable`, including `source: conflict`), so no
   *   sign-in method works here.
   */
  type InviteState =
    | 'loading'
    | 'signup_required'
    | 'signin_required'
    | 'restricted_host'
    | 'signin_unavailable'
    | 'direct_accept'
    | 'wrong_email'
    | 'already_accepted'
    | 'accepted'
    | 'declined'
    | 'invalid';

  // Terminal result of the in-session action. Once set, the state machine
  // pins to the accepted/declined view until the redirect fires, preventing
  // the action row from re-rendering during the redirect delay window.
  const actionResult = ref<'accepted' | 'declined' | null>(null);

  // Whether a signup attempt came back signup_unavailable, meaning signin is
  // the remaining path. Neither the show endpoint nor the signup endpoint
  // confirms account existence (AZ7 / #3856), so signup is the default entry
  // path and this flag only flips on that generic backend signal.
  const signinFallback = ref(false);

  const inviteState = computed<InviteState>(() => {
    if (isLoading.value) return 'loading';
    if (actionResult.value) return actionResult.value;
    // If loading finished but no invitation (API error), show invalid state
    if (!invitation.value) return 'invalid';

    // Check for non-actionable states first
    if (!invitation.value.actionable) {
      // Invitation exists but can't be acted upon
      if (invitation.value.status === 'active') return 'already_accepted';
      return 'invalid'; // expired, declined, revoked
    }

    // Invitation is actionable (pending, not expired)
    if (!authStore.isAuthenticated) {
      // ADR-034#invite-signup-is-gated (#4139). Only the UNAUTHENTICATED
      // branch consults the restriction: it governs which method may MINT a
      // session on this host, and every state below this line is about doing
      // exactly that. Once a session exists the restriction is spent — POST
      // /:token/accept is deliberately ungated (account-scoped,
      // ADR-034#reject-as-not-found-not-forbidden "Scope, settled") — so an
      // authenticated visitor must reach direct_accept even on a host that
      // restricts sign-in. This is what makes the invite-signup-is-gated
      // flow terminate: SSO signs them in, they come back here
      // authenticated, and they accept.
      if (signinUnavailable.value) return 'signin_unavailable';
      if (restrictedAway.value) return 'restricted_host';
      return signinFallback.value ? 'signin_required' : 'signup_required';
    }

    // User is authenticated
    if (emailMismatch.value) return 'wrong_email';
    return 'direct_accept';
  });

  /**
   * Server-resolved restriction for the host this page was served from
   * (ADR-034#resolution-is-model-owned). Read verbatim, never re-derived —
   * ADR-034#settings-api-serializes-effective-restrict-to deleted the
   * client-side re-derivation this would otherwise be.
   *
   * Absent means a pre-#4139 backend, which is treated as unrestricted so the
   * page behaves exactly as it did before this change.
   */
  const restrictToResolution = computed(() => invitation.value?.effective_restrict_to ?? null);

  /**
   * The restriction stands but nothing can satisfy it, so this host offers no
   * way to sign in at all.
   *
   * `source: 'conflict'` (global and domain naming different methods, which
   * has no intersection under A8) always resolves `unavailable`, so this one
   * check covers both; only the COPY branches on source.
   */
  const signinUnavailable = computed(() => restrictToResolution.value?.state === 'unavailable');

  /**
   * This host permits a single method and it is NOT password — i.e. the case
   * where the signup form below would POST into the A11 gate and 404.
   *
   * False when unrestricted, when restricted to password (nothing changes),
   * and when the resolution is unavailable (that is signinUnavailable's
   * state, and it must not also read as "use this other method").
   *
   * TRUE when `state` is `restricted` but `restrict_to` parsed to null: the
   * schema degrades an unrecognized method to null while `state` keeps
   * carrying the truth. A method this client version cannot name is still a
   * method it cannot offer, and treating it as unrestricted would put the
   * password form back in front of the gate — the exact fail-open this state
   * exists to close. The copy falls back to an unnamed variant.
   */
  const restrictedAway = computed(() => {
    const resolution = restrictToResolution.value;
    if (resolution?.state !== 'restricted') return false;
    return resolution.restrict_to !== 'password';
  });

  /** Method names, reused from the settings UI so both surfaces say one thing. */
  const METHOD_LABEL_KEYS: Record<SigninRestrictTo, string> = {
    password: 'web.domains.signin.method_password',
    email_auth: 'web.domains.signin.method_email_auth',
    webauthn: 'web.domains.signin.method_webauthn',
    sso: 'web.domains.signin.method_sso',
  };

  /** Human label for the restricted method, or null when it names none. */
  const restrictedMethodLabel = computed<string | null>(() => {
    const method = restrictToResolution.value?.restrict_to;
    return method ? t(METHOD_LABEL_KEYS[method]) : null;
  });

  type RoutableSsoMethod = Extract<AuthMethod, { type: 'sso' }> & {
    platform_route_name: string;
  };

  /** Routable tenant or platform-fallback SSO methods reported for this host. */
  const ssoMethods = computed(() =>
    (invitation.value?.auth_methods ?? []).filter(
      (entry): entry is RoutableSsoMethod =>
        entry.type === 'sso' && Boolean(entry.platform_route_name)
    )
  );

  /**
   * Whether the host's single permitted method is SSO — the one restricted
   * case this page can actually complete, by routing the invitee into the
   * provider (A11: SSO signs them in and creates the account cleanly, then
   * they return here authenticated and accept).
   */
  const ssoRestricted = computed(() => restrictToResolution.value?.restrict_to === 'sso');

  /**
   * Sign-in page, returning here afterwards. A string rather than a location
   * object to match the other router-links in this template.
   */
  const signinPath = computed(
    () => `/signin?redirect=${encodeURIComponent(`/invite/${invitationToken.value}`)}`
  );

  /**
   * Copy for the restricted-but-usable state.
   *
   * Every branch says the same two things: this host does not take the method
   * the form would have used, and the invitation is untouched. Nothing here
   * implies the invitation was consumed or lost — under A11 the gated signup
   * creates nothing, so it is still pending.
   */
  const restrictedNotice = computed(() => {
    if (ssoRestricted.value) {
      return t('web.organizations.invitations.restricted_sso_body');
    }
    const method = restrictedMethodLabel.value;
    return method
      ? t('web.organizations.invitations.restricted_host_body', { method })
      : t('web.organizations.invitations.restricted_host_unknown_body');
  });

  /**
   * Copy for the dead-end state, mirroring how the domain settings page
   * renders the same resolution.
   *
   * A conflict is named AS a conflict — `restrict_to` carries the global
   * method, the one still in force, and presenting it as the winner would
   * misdescribe a state where neither side applies.
   */
  const unavailableNotice = computed(() => {
    const resolution = restrictToResolution.value;
    const method = restrictedMethodLabel.value;
    if (resolution?.source === 'conflict' && method) {
      return t('web.organizations.invitations.signin_unavailable_conflict_body', { method });
    }
    return method
      ? t('web.organizations.invitations.signin_unavailable_body', { method })
      : t('web.organizations.invitations.signin_unavailable_unknown_body');
  });

  /**
   * Detects if the currently logged-in user has a different email
   * than the one the invitation was sent to (case-insensitive comparison).
   * When true, user must switch accounts - invitations are strictly email-bound.
   */
  const emailMismatch = computed(() => {
    if (!authStore.isAuthenticated || !invitation.value?.email) return false;
    const currentEmail = bootstrapStore.email;
    if (!currentEmail) return false;
    return currentEmail.toLowerCase() !== invitation.value.email.toLowerCase();
  });

  /**
   * Returns the organization's primary brand color, falling back to domain branding
   * or a default brand color.
   */
  const primaryColor = computed(
    () =>
      invitation.value?.branding?.primary_color ||
      bootstrapStore.domain_branding?.primary_color ||
      '#d45a2a'
  );

  /**
   * Logs out the current user and redirects back to the invite page.
   */
  async function handleContinueAs() {
    const token = invitationToken.value;
    await logout(`/invite/${token}`);
  }

  onMounted(async () => {
    const result = await wrap(async () => {
      const response = await $api.get(`/api/invite/${invitationToken.value}`);
      return showInviteResponseSchema.parse(response.data.record);
    });

    if (result) {
      invitation.value = result;

      // Set error messages for non-actionable states
      if (!result.actionable) {
        if (result.status === 'expired') {
          error.value = t('web.organizations.invitations.expired_message');
        } else if (result.status !== 'active') {
          error.value = t('web.organizations.invitations.invalid_token');
        }
      }
    } else {
      error.value = t('web.organizations.invitations.invalid_token');
    }

    isLoading.value = false;
  });

  const handleAccept = async () => {
    if (!authStore.isAuthenticated) {
      router.push({
        name: 'Sign In',
        query: {
          // Grandfathered: the sign-in form prefills from ?email= (see
          // src/router/README.md "Query-string policy"); the runtime guard
          // exempts /signin too. Migrating this needs /signin to read state.
          // eslint-disable-next-line ots/no-pii-in-query
          email: invitation.value?.email,
          redirect: `/invite/${invitationToken.value}`,
        },
      });
      return;
    }

    // If there's an email mismatch, don't proceed (user must switch accounts)
    if (emailMismatch.value) {
      return;
    }

    isProcessing.value = true;
    error.value = '';
    success.value = '';

    try {
      await $api.post(`/api/invite/${invitationToken.value}/accept`, {
        shrimp: csrfStore.shrimp,
      });

      // Reset organization store to force refetch on next mount
      organizationStore.$reset();

      actionResult.value = 'accepted';

      setTimeout(() => {
        router.push('/orgs');
      }, DIRECT_ACTION_REDIRECT_DELAY_MS);
    } catch (err) {
      const classified = classifyError(err);
      error.value = classified.message || t('web.organizations.invitations.accept_error');
    } finally {
      isProcessing.value = false;
    }
  };

  const handleDecline = async () => {
    isProcessing.value = true;
    error.value = '';

    try {
      await $api.post(`/api/invite/${invitationToken.value}/decline`);

      actionResult.value = 'declined';

      setTimeout(() => {
        router.push('/');
      }, DIRECT_ACTION_REDIRECT_DELAY_MS);
    } catch (err) {
      const classified = classifyError(err);
      error.value = classified.message || t('web.organizations.invitations.decline_error');
    } finally {
      isProcessing.value = false;
    }
  };

  const formatDate = (timestamp: number): string => formatDisplayDate(new Date(timestamp * 1000));

  /**
   * Handler for successful signup/signin (auth established, session live).
   *
   * Does NOT redirect — the invitation is still pending. The state machine
   * recomputes to direct_accept once authStore.isAuthenticated flips, which
   * renders the explicit Accept/Decline buttons. The user must click one.
   */
  function onAuthSuccess() {
    error.value = '';
    success.value = t('web.organizations.invitations.confirm_join_below');
  }

  /**
   * Handler for auth/accept errors from inline forms.
   */
  function onFormError(message: string) {
    error.value = message;
  }

  /**
   * Handler for MFA requirement during signin.
   * Redirects to MFA verification with return path to invitation.
   */
  function onMfaRequired(redirect: string) {
    router.push({ path: '/mfa-verify', query: { redirect } });
  }

  /**
   * Handler for when the backend reports signup is unavailable for this
   * invitation. Updates invitation state to offer the signin flow instead.
   */
  function onSigninRequired() {
    signinFallback.value = true;
  }
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-8 sm:px-6 lg:px-8">
    <!-- Loading State -->
    <div
      v-if="inviteState === 'loading'"
      data-testid="invite-loading"
      role="status"
      aria-busy="true"
      class="animate-pulse space-y-6 rounded-lg border border-gray-200 bg-white p-8 shadow-sm motion-reduce:animate-none dark:border-gray-700 dark:bg-gray-800">
      <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
      <!-- Heading block -->
      <Skeleton
        width="w-2/3"
        height="h-8"
        :pulse="false" />
      <!-- Invite-context lines -->
      <div class="space-y-3">
        <Skeleton
          width="w-1/2"
          height="h-4"
          :pulse="false" />
        <Skeleton
          width="w-3/4"
          height="h-4"
          :pulse="false" />
        <Skeleton
          width="w-2/5"
          height="h-4"
          :pulse="false" />
      </div>
      <!-- Action button block -->
      <Skeleton
        width="w-full"
        height="h-10"
        rounded="rounded-md"
        :pulse="false" />
    </div>

    <!-- Invalid/Expired State -->
    <div
      v-else-if="inviteState === 'invalid'"
      data-testid="invite-invalid"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="x-circle"
          class="mx-auto size-12 text-red-500 dark:text-red-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.invitation_details') }}
        </h1>
      </div>

      <BasicFormAlerts
        v-if="error"
        :error="error" />

      <div class="mt-6 text-center">
        <router-link
          to="/"
          class="text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          {{ t('web.organizations.invitations.back_to_home') }}
        </router-link>
      </div>
    </div>

    <!-- Already Accepted State -->
    <div
      v-else-if="inviteState === 'already_accepted'"
      data-testid="invite-already-accepted"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="check-circle"
          class="mx-auto size-12 text-green-500 dark:text-green-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.invitation_details') }}
        </h1>
      </div>

      <div
        class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <div class="flex">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 text-blue-400"
            aria-hidden="true" />
          <div class="ml-3">
            <p class="text-sm text-blue-800 dark:text-blue-400">
              {{ t('web.organizations.invitations.already_member') }}
            </p>
          </div>
        </div>
      </div>

      <div class="mt-6 text-center">
        <router-link
          to="/orgs"
          class="inline-flex items-center rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
          {{ t('web.organizations.invitations.go_to_organizations') }}
        </router-link>
      </div>
    </div>

    <!-- Terminal Action State (just accepted or declined in this session) -->
    <div
      v-else-if="inviteState === 'accepted' || inviteState === 'declined'"
      :data-testid="inviteState === 'accepted' ? 'invite-accepted' : 'invite-declined'"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <div class="text-center">
        <OIcon
          collection="heroicons"
          :name="inviteState === 'accepted' ? 'check-circle' : 'x-circle'"
          :class="[
            'mx-auto size-12',
            inviteState === 'accepted'
              ? 'text-green-500 dark:text-green-400'
              : 'text-gray-400 dark:text-gray-500',
          ]"
          aria-hidden="true" />
        <p class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{
            inviteState === 'accepted'
              ? t('web.organizations.invitations.accept_success')
              : t('web.organizations.invitations.decline_success')
          }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.COMMON.redirecting') }}
        </p>
      </div>
    </div>

    <!-- Signup Required State (new user, no account) -->
    <div
      v-else-if="inviteState === 'signup_required'"
      data-testid="invite-signup-required"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.accept_invitation') }}
        </h1>
      </div>

      <BasicFormAlerts
        v-if="success"
        :success="success" />

      <!-- Invite Context (org name, role, inviter) -->
      <div
        v-if="invitation"
        data-testid="invitation-context"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
          <p
            v-if="invitation.invited_by"
            class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a
            <span class="text-gray-600 dark:text-gray-300">{{
              t(`web.organizations.invitations.roles.${invitation.role}`)
            }}</span>.
          </p>
        </div>
      </div>

      <!-- Inline Signup Form (handles its own error display) -->
      <InviteSignUpForm
        v-if="invitation"
        :invited-email="invitation.email"
        :invite-token="invitationToken"
        :org-name="invitation.organization_name"
        :auth-methods="invitation.auth_methods || []"
        @success="onAuthSuccess"
        @error="onFormError"
        @decline="handleDecline"
        @signin-required="onSigninRequired" />

      <p
        v-if="invitation"
        class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.invitations.expires_at') }}
        <span class="font-medium text-gray-900 dark:text-white">{{
          formatDate(invitation.expires_at)
        }}</span>
      </p>
    </div>

    <!-- Signin Required State (existing user, must authenticate) -->
    <div
      v-else-if="inviteState === 'signin_required'"
      data-testid="invite-signin-required"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.accept_invitation') }}
        </h1>
      </div>

      <BasicFormAlerts
        v-if="success"
        :success="success" />

      <!-- Invite Context (org name, role, inviter) -->
      <div
        v-if="invitation"
        data-testid="invitation-context"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
          <p
            v-if="invitation.invited_by"
            class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a
            <span class="text-gray-600 dark:text-gray-300">{{
              t(`web.organizations.invitations.roles.${invitation.role}`)
            }}</span>.
          </p>
        </div>
      </div>

      <!-- Sign-in Notice -->
      <div class="mt-6">
        <div
          data-testid="sign-in-notice"
          class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="size-5 text-blue-400"
              aria-hidden="true" />
            <div class="ml-3">
              <p class="text-sm text-blue-800 dark:text-blue-400">
                {{ t('web.organizations.invitations.must_sign_in') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Inline Sign-in Form -->
        <InviteSignInForm
          v-if="invitation"
          :invited-email="invitation.email"
          :invite-token="invitationToken"
          :org-name="invitation.organization_name"
          :auth-methods="invitation.auth_methods || []"
          @success="onAuthSuccess"
          @error="onFormError"
          @mfa-required="onMfaRequired"
          @decline="handleDecline" />
      </div>

      <p
        v-if="invitation"
        class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.invitations.expires_at') }}
        <span class="font-medium text-gray-900 dark:text-white">{{
          formatDate(invitation.expires_at)
        }}</span>
      </p>
    </div>

    <!--
      Restricted Host State (ADR-034#invite-signup-is-gated, #4139)

      This host restricts sign-in to a single method that is not password, so
      POST /api/invite/:token/signup 404s and creates nothing. Render the
      method the host actually offers instead of a form that cannot submit.
    -->
    <div
      v-else-if="inviteState === 'restricted_host'"
      data-testid="invite-restricted-host"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.accept_invitation') }}
        </h1>
      </div>

      <!-- Invite Context (org name, role, inviter) -->
      <div
        v-if="invitation"
        data-testid="invitation-context"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
          <p
            v-if="invitation.invited_by"
            class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a
            <span class="text-gray-600 dark:text-gray-300">{{
              t(`web.organizations.invitations.roles.${invitation.role}`)
            }}</span>.
          </p>
        </div>
      </div>

      <!--
        Announced, not implied by color: role="status" + aria-live carry this
        to assistive tech, the heading states the constraint in words, and the
        icon is decorative. Fixed semantic sky/info hue (#4132) rather than a
        brand token — this is a status claim and must read the same on every
        domain.
      -->
      <div
        class="mt-6 rounded-lg border border-sky-200 bg-sky-50 p-4 dark:border-sky-800 dark:bg-sky-950/40"
        data-testid="restricted-host-notice"
        role="status"
        aria-live="polite">
        <div class="flex">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 shrink-0 text-sky-600 dark:text-sky-300"
            aria-hidden="true" />
          <div class="ml-3">
            <p class="font-medium text-sky-800 dark:text-sky-100">
              {{ t('web.organizations.invitations.restricted_host_title') }}
            </p>
            <p class="mt-1 text-sm text-sky-700 dark:text-sky-200">
              {{ restrictedNotice }}
            </p>
            <!--
              The invitation is NOT consumed by the gated signup (A11 creates
              nothing), so say so plainly rather than leaving the invitee to
              assume they burned their link.
            -->
            <p class="mt-2 text-sm text-sky-700 dark:text-sky-200">
              {{ t('web.organizations.invitations.invitation_stays_pending') }}
            </p>
          </div>
        </div>
      </div>

      <!-- SSO: route directly when the API supplied usable provider metadata. -->
      <div
        v-if="ssoRestricted && ssoMethods.length > 0"
        class="mt-6 space-y-3">
        <SsoButton
          v-for="method in ssoMethods"
          :key="method.platform_route_name"
          :route-name="method.platform_route_name!"
          :display-name="method.display_name ?? undefined"
          :redirect="`/invite/${invitationToken}`" />
      </div>

      <!--
        Canonical SSO and restricted email-auth/webauthn are completed by the
        sign-in page. Preserve the invite return path so this handoff cannot
        loop back to the same unauthenticated static invite state.
      -->
      <router-link
        v-else
        :to="signinPath"
        data-testid="restricted-signin-link"
        class="mt-6 inline-flex w-full justify-center rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
        {{
          ssoRestricted
            ? t('web.organizations.invitations.restricted_sso_cta')
            : t('web.login.button_sign_in')
        }}
      </router-link>

      <p
        v-if="invitation"
        class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.invitations.expires_at') }}
        <span class="font-medium text-gray-900 dark:text-white">{{
          formatDate(invitation.expires_at)
        }}</span>
      </p>
    </div>

    <!--
      Sign-in Unavailable State
      (ADR-034#degradation-is-fail-closed / #resolution-intersects-never-widens, #4139)

      The host's restriction stands but cannot be honoured — its method cannot
      run here, or global and domain name different methods and neither
      applies. No sign-in method works, so offer none and say why.
    -->
    <div
      v-else-if="inviteState === 'signin_unavailable'"
      data-testid="invite-signin-unavailable"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.invitation_details') }}
        </h1>
      </div>

      <!-- Invite Context (org name, role, inviter) -->
      <div
        v-if="invitation"
        data-testid="invitation-context"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
          <p
            v-if="invitation.invited_by"
            class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a
            <span class="text-gray-600 dark:text-gray-300">{{
              t(`web.organizations.invitations.roles.${invitation.role}`)
            }}</span>.
          </p>
        </div>
      </div>

      <!--
        role="alert": a dead end the invitee cannot work around here, so it is
        announced assertively. Fixed semantic amber/warning hue (#4132). Not
        red — nothing is broken about the invitation itself, and the wording
        keeps that distinct from a bad token.
      -->
      <div
        class="mt-6 rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-950/40"
        data-testid="signin-unavailable-notice"
        role="alert">
        <div class="flex">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            class="size-5 shrink-0 text-amber-600 dark:text-amber-300"
            aria-hidden="true" />
          <div class="ml-3">
            <p class="font-medium text-amber-800 dark:text-amber-100">
              {{ t('web.organizations.invitations.signin_unavailable_title') }}
            </p>
            <p class="mt-1 text-sm text-amber-700 dark:text-amber-200">
              {{ unavailableNotice }}
            </p>
            <p class="mt-2 text-sm text-amber-700 dark:text-amber-200">
              {{ t('web.organizations.invitations.invitation_stays_pending') }}
            </p>
          </div>
        </div>
      </div>

      <p
        data-testid="restricted-use-email-link"
        class="mt-6 text-center text-sm text-gray-600 dark:text-gray-300">
        {{ t('web.organizations.invitations.restricted_use_email_link') }}
      </p>

      <p
        v-if="invitation"
        class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.invitations.expires_at') }}
        <span class="font-medium text-gray-900 dark:text-white">{{
          formatDate(invitation.expires_at)
        }}</span>
      </p>
    </div>

    <!-- Direct Accept State (authenticated, correct email) -->
    <div
      v-else-if="inviteState === 'direct_accept'"
      data-testid="invite-direct-accept"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.invitation_details') }}
        </h1>
      </div>

      <BasicFormAlerts
        v-if="error"
        :error="error" />
      <BasicFormAlerts
        v-if="success"
        :success="success" />

      <!-- Invitation Details -->
      <div
        v-if="invitation"
        data-testid="invitation-details"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
          <p
            v-if="invitation.invited_by"
            class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a
            <span class="text-gray-600 dark:text-gray-300">{{
              t(`web.organizations.invitations.roles.${invitation.role}`)
            }}</span>.
          </p>
        </div>

        <!-- Action Buttons -->
        <div class="mt-6 flex flex-col gap-3 sm:flex-row-reverse">
          <button
            type="button"
            @click="handleAccept"
            :disabled="isProcessing"
            data-testid="accept-invitation-btn"
            class="inline-flex w-full justify-center rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto dark:bg-brand-500 dark:hover:bg-brand-400">
            <span v-if="!isProcessing">
              {{ t('web.organizations.invitations.accept_invitation') }}
            </span>
            <span v-else>{{ t('web.COMMON.processing') }}</span>
          </button>
          <button
            type="button"
            @click="handleDecline"
            :disabled="isProcessing"
            data-testid="decline-invitation-btn"
            class="inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
            {{ t('web.organizations.invitations.decline_invitation') }}
          </button>
        </div>

        <p class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.expires_at') }}
          <span class="font-medium text-gray-900 dark:text-white">{{
            formatDate(invitation.expires_at)
          }}</span>
        </p>
      </div>
    </div>

    <!-- Wrong Email State (authenticated, mismatch) -->
    <div
      v-else-if="inviteState === 'wrong_email'"
      data-testid="invite-wrong-email"
      :style="{ '--brand-primary': primaryColor }"
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.invitation_details') }}
        </h1>
      </div>

      <BasicFormAlerts
        v-if="error"
        :error="error" />
      <BasicFormAlerts
        v-if="success"
        :success="success" />

      <!-- Invitation Details -->
      <div
        v-if="invitation"
        data-testid="invitation-details"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
          <p
            v-if="invitation.invited_by"
            class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a
            <span class="text-gray-600 dark:text-gray-300">{{
              t(`web.organizations.invitations.roles.${invitation.role}`)
            }}</span>.
          </p>
        </div>

        <!-- Email Mismatch Notice -->
        <div
          data-testid="email-mismatch-warning"
          class="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="size-5 shrink-0 text-amber-500"
              aria-hidden="true" />
            <div class="ml-3">
              <p class="font-medium text-amber-800 dark:text-amber-200">
                {{ t('web.organizations.invitations.email_mismatch_title') }}
              </p>
              <p class="mt-1 text-sm text-amber-700 dark:text-amber-300">
                {{
                  t('web.organizations.invitations.email_mismatch_body', {
                    invitedEmail: invitation?.email,
                    currentEmail: bootstrapStore.email,
                  })
                }}
              </p>
              <div class="mt-3">
                <button
                  type="button"
                  @click="handleContinueAs"
                  :disabled="isProcessing"
                  data-testid="continue-as-btn"
                  class="inline-flex items-center rounded-md bg-amber-100 px-3 py-1.5 text-sm font-medium text-amber-800 hover:bg-amber-200 focus:ring-2 focus:ring-amber-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-800 dark:text-amber-100 dark:hover:bg-amber-700">
                  {{
                    t('web.organizations.invitations.continue_as_invited_email', {
                      email: invitation?.email,
                    })
                  }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-6 text-center">
          <button
            type="button"
            @click="handleDecline"
            :disabled="isProcessing"
            data-testid="decline-invitation-btn"
            class="text-sm font-medium text-gray-500 underline hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.organizations.invitations.decline_invitation') }}
          </button>
        </div>

        <p class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.expires_at') }}
          <span class="font-medium text-gray-900 dark:text-white">{{
            formatDate(invitation.expires_at)
          }}</span>
        </p>
      </div>
    </div>
  </div>
</template>
