<!-- src/apps/session/views/Reauth.vue -->

<script setup lang="ts">
  import AuthView from '@/apps/session/components/AuthView.vue';
  import { useReauth } from '@/shared/composables/useReauth';
  import { isValidInternalPath } from '@/utils/redirect';
  import { computed, onMounted, ref } from 'vue';
  import { useRoute, useRouter } from 'vue-router';

  type PasswordStep = 'password' | 'otp' | 'recovery' | 'webauthn';

  const route = useRoute();
  const router = useRouter();
  const {
    offer,
    mfaMethods,
    isLoading,
    error,
    webauthnSupported,
    clearError,
    fetchOffer,
    submitPassword,
    submitPasswordWebauthn,
    submitWebauthn,
  } = useReauth();

  const password = ref('');
  const otpCode = ref('');
  const recoveryCode = ref('');
  const passwordStep = ref<PasswordStep>('password');

  const passwordOffered = computed(() => offer.value?.methods.includes('password') === true);
  const webauthnOffered = computed(() => offer.value?.methods.includes('webauthn') === true);
  const otpOffered = computed(() =>
    mfaMethods.value.some((method) => method === 'otp' || method === 'otp_code')
  );
  const recoveryOffered = computed(() =>
    mfaMethods.value.some(
      (method) => method === 'recovery' || method === 'recovery_code' || method === 'recovery_codes'
    )
  );
  const webauthnMfaOffered = computed(() => mfaMethods.value.includes('webauthn'));

  function safeRedirect(): string {
    const candidate = route.query.redirect;
    if (typeof candidate !== 'string' || !isValidInternalPath(candidate)) return '/';

    try {
      return router.resolve(candidate).path === '/reauth' ? '/' : candidate;
    } catch {
      return '/';
    }
  }

  async function complete(result: Awaited<ReturnType<typeof submitPassword>>) {
    if (result === 'success') {
      await router.replace(safeRedirect());
      return;
    }

    if (result === 'mfa_required') {
      if (otpOffered.value) {
        passwordStep.value = 'otp';
      } else if (webauthnMfaOffered.value) {
        passwordStep.value = 'webauthn';
      } else if (recoveryOffered.value) {
        passwordStep.value = 'recovery';
      }
    }
  }

  async function handlePassword() {
    if (!password.value) return;
    await complete(await submitPassword(password.value));
  }

  async function handleOtp() {
    if (!otpCode.value.trim()) return;
    await complete(await submitPassword(password.value, otpCode.value.trim()));
  }

  async function handleRecovery() {
    if (!recoveryCode.value.trim()) return;
    await complete(await submitPassword(password.value, undefined, recoveryCode.value.trim()));
  }

  async function handleWebauthn() {
    await complete(await submitWebauthn());
  }

  async function handlePasswordWebauthn() {
    await complete(await submitPasswordWebauthn(password.value));
  }

  function switchPasswordStep(step: PasswordStep) {
    clearError();
    passwordStep.value = step;
    otpCode.value = '';
    recoveryCode.value = '';
  }

  onMounted(fetchOffer);
</script>

<template>
  <AuthView
    heading="Confirm it’s you"
    heading-id="reauth-heading"
    :with-subheading="false"
    :show-return-home="false">
    <template #form>
      <div
        class="space-y-6"
        data-testid="reauth-view">
        <p class="text-center text-sm text-gray-600 dark:text-gray-300">
          Re-authenticate to continue to this protected action.
        </p>

        <div
          v-if="isLoading && !offer"
          class="py-6 text-center text-sm text-gray-600 dark:text-gray-300"
          role="status"
          aria-live="polite">
          Loading authentication options…
        </div>

        <template v-else-if="offer">
          <form
            v-if="passwordOffered && passwordStep === 'password'"
            class="space-y-4"
            data-testid="reauth-password-form"
            @submit.prevent="handlePassword">
            <div>
              <label
                for="reauth-password"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-200">
                Password
              </label>
              <input
                id="reauth-password"
                v-model="password"
                type="password"
                autocomplete="current-password"
                required
                :disabled="isLoading"
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:opacity-60 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
            </div>
            <button
              type="submit"
              :disabled="isLoading || !password"
              class="w-full rounded-md bg-brand-600 px-4 py-3 font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50">
              {{ isLoading ? 'Verifying…' : 'Continue' }}
            </button>
          </form>

          <form
            v-else-if="passwordStep === 'otp'"
            class="space-y-4"
            data-testid="reauth-otp-form"
            @submit.prevent="handleOtp">
            <div>
              <label
                for="reauth-otp"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-200">
                Authentication code
              </label>
              <input
                id="reauth-otp"
                v-model="otpCode"
                type="text"
                inputmode="numeric"
                autocomplete="one-time-code"
                required
                :disabled="isLoading"
                class="block w-full rounded-md border-gray-300 text-center font-mono tracking-widest shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:opacity-60 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
            </div>
            <button
              type="submit"
              :disabled="isLoading || !otpCode.trim()"
              class="w-full rounded-md bg-brand-600 px-4 py-3 font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50">
              {{ isLoading ? 'Verifying…' : 'Verify code' }}
            </button>
            <button
              v-if="recoveryOffered"
              type="button"
              class="w-full text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400"
              @click="switchPasswordStep('recovery')">
              Use a recovery code
            </button>
          </form>

          <div
            v-else-if="passwordStep === 'webauthn'"
            class="space-y-4"
            data-testid="reauth-password-webauthn">
            <p class="text-center text-sm text-gray-600 dark:text-gray-300">
              Complete the required passkey check.
            </p>
            <button
              type="button"
              :disabled="isLoading || !webauthnSupported"
              class="w-full rounded-md bg-brand-600 px-4 py-3 font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
              @click="handlePasswordWebauthn">
              {{ isLoading ? 'Waiting for passkey…' : 'Use a passkey' }}
            </button>
            <button
              v-if="otpOffered"
              type="button"
              class="w-full text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400"
              @click="switchPasswordStep('otp')">
              Use an authentication code
            </button>
            <button
              v-if="recoveryOffered"
              type="button"
              class="w-full text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400"
              @click="switchPasswordStep('recovery')">
              Use a recovery code
            </button>
          </div>

          <form
            v-else-if="passwordStep === 'recovery'"
            class="space-y-4"
            data-testid="reauth-recovery-form"
            @submit.prevent="handleRecovery">
            <div>
              <label
                for="reauth-recovery"
                class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-200">
                Recovery code
              </label>
              <input
                id="reauth-recovery"
                v-model="recoveryCode"
                type="text"
                autocomplete="off"
                required
                :disabled="isLoading"
                class="block w-full rounded-md border-gray-300 font-mono shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:opacity-60 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
            </div>
            <button
              type="submit"
              :disabled="isLoading || !recoveryCode.trim()"
              class="w-full rounded-md bg-brand-600 px-4 py-3 font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50">
              {{ isLoading ? 'Verifying…' : 'Verify recovery code' }}
            </button>
            <button
              v-if="otpOffered"
              type="button"
              class="w-full text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400"
              @click="switchPasswordStep('otp')">
              Use an authentication code
            </button>
          </form>

          <div
            v-if="webauthnOffered && passwordStep === 'password'"
            class="space-y-3">
            <div
              v-if="passwordOffered"
              class="flex items-center gap-3"
              aria-hidden="true">
              <div class="h-px flex-1 bg-gray-200 dark:bg-gray-600"></div>
              <span class="text-xs text-gray-500 uppercase dark:text-gray-400">or</span>
              <div class="h-px flex-1 bg-gray-200 dark:bg-gray-600"></div>
            </div>
            <button
              type="button"
              data-testid="reauth-webauthn-submit"
              :disabled="isLoading || !webauthnSupported"
              class="w-full rounded-md border border-gray-300 px-4 py-3 font-medium text-gray-800 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-100 dark:hover:bg-gray-700"
              @click="handleWebauthn">
              {{ isLoading ? 'Waiting for passkey…' : 'Use a passkey' }}
            </button>
            <p
              v-if="!webauthnSupported"
              class="text-center text-sm text-gray-600 dark:text-gray-400">
              Passkeys are not supported by this browser.
            </p>
          </div>

          <div
            v-if="offer.methods.length === 0"
            class="rounded-md bg-yellow-50 p-4 text-sm text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-200"
            role="alert">
            No re-authentication method is available for this account on this site.
          </div>
        </template>

        <div
          v-if="error"
          class="rounded-md bg-red-50 p-4 text-sm text-red-800 dark:bg-red-900/20 dark:text-red-200"
          role="alert"
          aria-live="assertive"
          data-testid="reauth-error">
          {{ error }}
        </div>

        <button
          type="button"
          class="w-full text-sm text-gray-600 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200"
          @click="router.replace('/')">
          Cancel
        </button>
      </div>
    </template>
  </AuthView>
</template>
