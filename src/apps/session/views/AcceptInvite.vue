<!-- src/apps/session/views/AcceptInvite.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import InviteSignUpForm from '@/apps/session/components/InviteSignUpForm.vue';
  import InviteSignInForm from '@/apps/session/components/InviteSignInForm.vue';
  import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
  import { classifyError } from '@/schemas/errors';
  import { useAuth } from '@/shared/composables/useAuth';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useCsrfStore } from '@/shared/stores/csrfStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { formatDisplayDate } from '@/utils/format';
  import { onMounted, ref, computed } from 'vue';
  import { useRoute, useRouter } from 'vue-router';
  import { useApi } from '@/shared/composables/useApi';
  import {
    showInviteResponseSchema,
    type ShowInviteResponse,
  } from '@/schemas/api/invite/responses/show-invite';

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

  // Delay before redirecting so the success message is visible and the
  // background authStore sync (fire-and-forget from useInviteAuth) has time
  // to settle before /orgs mounts and queries the store.
  const ACCEPT_SUCCESS_REDIRECT_DELAY_MS = 1500;
  // Longer delay for the direct accept/decline paths where the server has
  // already confirmed and no background auth sync is pending.
  const DIRECT_ACTION_REDIRECT_DELAY_MS = 2000;

  const invitationToken = ref<string>(route.params.token as string);
  const invitation = ref<ShowInviteResponse | null>(null);

  const isLoading = ref(true);
  const error = ref('');
  const success = ref('');
  const isProcessing = ref(false);

  /**
   * Invite state machine - 6 possible states
   *
   * States:
   * - loading: Initial fetch in progress
   * - signup_required: Unauthenticated, no existing account for invited email
   * - signin_required: Unauthenticated, account exists for invited email
   * - direct_accept: Authenticated with correct email, can accept immediately
   * - wrong_email: Authenticated but with different email than invitation
   * - already_accepted: Invitation was already accepted (status: active)
   * - invalid: Invitation is expired, declined, revoked, or doesn't exist
   */
  type InviteState =
    | 'loading'
    | 'signup_required'
    | 'signin_required'
    | 'direct_accept'
    | 'wrong_email'
    | 'already_accepted'
    | 'invalid';

  const inviteState = computed<InviteState>(() => {
    if (isLoading.value) return 'loading';
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
      return invitation.value.account_exists ? 'signin_required' : 'signup_required';
    }

    // User is authenticated
    if (emailMismatch.value) return 'wrong_email';
    return 'direct_accept';
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
  const primaryColor = computed(() => invitation.value?.branding?.primary_color || bootstrapStore.domain_branding?.primary_color || '#d45a2a');

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

      success.value = t('web.organizations.invitations.accept_success');

      // Reset organization store to force refetch on next mount
      organizationStore.$reset();

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

      // Update local state to hide invitation details immediately
      if (invitation.value) {
        invitation.value.status = 'declined';
      }
      success.value = t('web.organizations.invitations.decline_success');

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
   * Handler for successful signup/signin + accept flow.
   * Redirects to organizations page.
   */
  function onAcceptSuccess() {
    success.value = t('web.organizations.invitations.accept_success');
    // Reset organization store to force refetch on next mount
    organizationStore.$reset();
    setTimeout(() => {
      router.push('/orgs');
    }, ACCEPT_SUCCESS_REDIRECT_DELAY_MS);
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
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-8 sm:px-6 lg:px-8">
    <!-- Loading State -->
    <div
      v-if="inviteState === 'loading'"
      data-testid="invite-loading"
      class="flex items-center justify-center py-12">
      <div class="text-center">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          class="mx-auto size-8 animate-spin text-gray-400"
          aria-hidden="true" />
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.loading_invitation') }}
        </p>
      </div>
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

      <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
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
        v-if="error"
        :error="error" />
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
          <p v-if="invitation.invited_by_email" class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by_email }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a <span class="text-gray-600 dark:text-gray-300">{{ t(`web.organizations.invitations.roles.${invitation.role}`) }}</span>.
          </p>
        </div>

      </div>

      <!-- Inline Signup Form -->
      <InviteSignUpForm
        v-if="invitation"
        :invited-email="invitation.email"
        :invite-token="invitationToken"
        :org-name="invitation.organization_name"
        :auth-methods="invitation.auth_methods || []"
        @success="onAcceptSuccess"
        @error="onFormError"
        @decline="handleDecline" />

      <p v-if="invitation" class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.invitations.expires_at') }}
        <span class="font-medium text-gray-900 dark:text-white">{{ formatDate(invitation.expires_at) }}</span>
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
        v-if="error"
        :error="error" />
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
          <p v-if="invitation.invited_by_email" class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by_email }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a <span class="text-gray-600 dark:text-gray-300">{{ t(`web.organizations.invitations.roles.${invitation.role}`) }}</span>.
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
          @success="onAcceptSuccess"
          @error="onFormError"
          @mfa-required="onMfaRequired"
          @decline="handleDecline" />
      </div>

      <p v-if="invitation" class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.invitations.expires_at') }}
        <span class="font-medium text-gray-900 dark:text-white">{{ formatDate(invitation.expires_at) }}</span>
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
          <p v-if="invitation.invited_by_email" class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by_email }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a <span class="text-gray-600 dark:text-gray-300">{{ t(`web.organizations.invitations.roles.${invitation.role}`) }}</span>.
          </p>
        </div>


        <!-- Action Buttons -->
        <div class="mt-6 flex flex-col gap-3 sm:flex-row-reverse">
          <button
            type="button"
            @click="handleAccept"
            :disabled="isProcessing"
            data-testid="accept-invitation-btn"
            class="inline-flex w-full justify-center rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400 sm:w-auto">
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
            class="inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600 sm:w-auto">
            {{ t('web.organizations.invitations.decline_invitation') }}
          </button>
        </div>

        <p class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.expires_at') }}
          <span class="font-medium text-gray-900 dark:text-white">{{ formatDate(invitation.expires_at) }}</span>
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
          <p v-if="invitation.invited_by_email" class="mt-1 text-sm text-gray-400 dark:text-gray-500">
            by <span class="text-gray-600 dark:text-gray-300">{{ invitation.invited_by_email }}</span>
          </p>
          <p class="text-sm text-gray-400 dark:text-gray-500">
            as a <span class="text-gray-600 dark:text-gray-300">{{ t(`web.organizations.invitations.roles.${invitation.role}`) }}</span>.
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
                {{ t('web.organizations.invitations.email_mismatch_body', { invitedEmail: invitation?.email, currentEmail: bootstrapStore.email }) }}
              </p>
              <div class="mt-3">
                <button
                  type="button"
                  @click="handleContinueAs"
                  :disabled="isProcessing"
                  data-testid="continue-as-btn"
                  class="inline-flex items-center rounded-md bg-amber-100 px-3 py-1.5 text-sm font-medium text-amber-800 hover:bg-amber-200 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-800 dark:text-amber-100 dark:hover:bg-amber-700">
                  {{ t('web.organizations.invitations.continue_as_invited_email', { email: invitation?.email }) }}
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
            class="text-sm font-medium text-gray-500 underline hover:text-gray-700
                   dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.organizations.invitations.decline_invitation') }}
          </button>
        </div>

        <p class="mt-4 text-center text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.expires_at') }}
          <span class="font-medium text-gray-900 dark:text-white">{{ formatDate(invitation.expires_at) }}</span>
        </p>
      </div>
    </div>
  </div>
</template>
