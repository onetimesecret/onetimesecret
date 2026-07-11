<!-- src/apps/secret/conceal/BrandedHomepage.vue -->

<script setup lang="ts">
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import IncomingSecretFormBody from '@/apps/secret/components/incoming/IncomingSecretFormBody.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { useIncomingStore } from '@/shared/stores/incomingStore';
  import { storeToRefs } from 'pinia';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const identityStore = useProductIdentity();
  // storeToRefs (not destructuring) so in-session config changes — e.g. an
  // admin flipping the homepage mode from the workspace — stay reactive.
  const {
    allowPublicHomepage,
    homepageSecretsMode,
    primaryColor,
    cornerClass,
    headingFontClass,
    fontFamilyClass,
    buttonTextLight,
    logoUri,
    displayName,
  } = storeToRefs(identityStore);

  const incomingMode = computed(
    () => allowPublicHomepage.value && homepageSecretsMode.value === 'incoming'
  );

  // ---------------------------------------------------------------------
  // Incoming form availability (incoming mode only)
  //
  // The bootstrap payload only says incoming mode is active when the
  // backend judged it servable, but the config still loads at runtime and
  // can fail (entitlement lapse, recipients emptied moments ago, network).
  // Any such failure degrades to the same private trust card the disabled
  // homepage shows — an anonymous visitor must never see upgrade/billing
  // or misconfiguration copy on the branded front door.
  // ---------------------------------------------------------------------

  const incomingStore = useIncomingStore();
  const incomingLoading = ref(false);

  const incomingAvailable = computed(
    () =>
      !incomingStore.isEntitlementBlocked &&
      !incomingStore.configError &&
      incomingStore.isFeatureEnabled &&
      incomingStore.recipients.length > 0
  );

  // Load whenever incoming mode becomes active — immediate covers initial
  // render; the watch covers an in-session mode change (an admin flipping
  // the homepage selector from the workspace patches bootstrapStore live).
  watch(
    incomingMode,
    async (active) => {
      if (!active || incomingLoading.value) return;
      incomingLoading.value = true;
      try {
        await incomingStore.loadConfig();
      } catch {
        // Degrade to the trust card; the store captures error state.
      } finally {
        incomingLoading.value = false;
      }
    },
    { immediate: true }
  );

  const showIncomingForm = computed(
    () => incomingMode.value && !incomingLoading.value && incomingAvailable.value
  );
  const showTrustCard = computed(
    () =>
      !allowPublicHomepage.value ||
      (incomingMode.value && !incomingLoading.value && !incomingAvailable.value)
  );

  // Send-a-secret copy only while the incoming form is (or is about to be)
  // the content below it. Once the runtime check degrades incoming to the
  // trust card, fall back to the neutral copy the private branch has always
  // shown — a "Send a secret" headline over a members-only notice reads as
  // a broken page.
  const incomingCopy = computed(
    () => incomingMode.value && (incomingLoading.value || incomingAvailable.value)
  );
  const headline = computed(() =>
    incomingCopy.value
      ? t('web.homepage.send_a_secret')
      : t('web.homepage.create_a_secure_link')
  );
  const subline = computed(() =>
    incomingCopy.value
      ? t('web.homepage.deliver_sensitive_information_directly_and_securely')
      : t('web.homepage.send_sensitive_information_that_can_only_be_viewed_once')
  );

  // Handle logo 404 errors gracefully
  const imageError = ref(false);
  const handleImageError = () => {
    imageError.value = true;
  };
</script>

<template>
  <div
    :class="fontFamilyClass"
    class="relative mx-auto w-full max-w-xl px-4">
    <!-- Logo + Taglines (centered brand hero for custom domains) -->
    <div class="mb-8 text-center">
      <!-- Logo with error handling - hides if 404 -->
      <!--
        Sizing: a fixed height with `w-auto max-w-full` lets wide, rectangular
        logos (common when they include the company name) use the full column
        width instead of being squeezed by a narrow max-width and rendering
        comically small.

        Corner radius: the logo reflects the brand radius (cornerClass) — a
        product requirement. The browser clamps `--radius-brand` to half the
        image's shorter side, so a pill/full radius rounds the ends rather than
        overflowing.
      -->
      <div
        v-if="logoUri && !imageError"
        class="mb-8 flex justify-center">
        <img
          :src="logoUri"
          :class="cornerClass"
          class="h-16 w-auto max-w-full object-contain sm:h-20"
          :alt="displayName"
          @error="handleImageError" />
      </div>
      <h1
        :class="headingFontClass"
        class="text-2xl font-semibold text-gray-900 dark:text-white">
        {{ headline }}
      </h1>
      <p class="mt-2 text-gray-600 dark:text-gray-300">
        {{ subline }}
      </p>
    </div>

    <!--
      Custom Domain Homepage (branded landing for self-hosted workspaces)

      Audiences:
      - Recipients arriving via a shared link
      - Team members who need to sign in (via TransactionalHeader)
      - Admins verifying the branded landing page

      Design notes:
      - Minimal, trust-focused with brand color accents
      - Sign In handled at layout level, not here
      - Public create mode: shows the secret creation form
      - Public incoming mode (secrets_mode=incoming): shows the incoming
        secrets form; degrades to the private trust card if incoming
        becomes unavailable at runtime
      - Private mode: status card with trust signals, no form
    -->

    <!-- Public create mode: secret form -->
    <SecretForm
      v-if="allowPublicHomepage && !incomingMode"
      class="mb-8"
      :primary-color="primaryColor"
      :button-text-light="buttonTextLight"
      :corner-class="cornerClass"
      :with-recipient="false"
      :with-asterisk="false"
      :with-generate="false" />

    <!-- Public incoming mode: send-a-secret form -->
    <IncomingSecretFormBody
      v-else-if="showIncomingForm"
      class="mb-8"
      data-testid="homepage-incoming-form"
      :primary-color="primaryColor" />

    <!-- Incoming config loading: quiet placeholder to avoid a content flash -->
    <div
      v-else-if="incomingMode && incomingLoading"
      class="mb-8 flex justify-center py-12"
      data-testid="homepage-incoming-loading">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        class="size-6 animate-spin text-gray-400"
        aria-hidden="true" />
    </div>

    <!-- Private (or incoming unavailable): trust signals only -->
    <div
      v-else-if="showTrustCard"
      class="space-y-8">
      <!-- Status Card -->
      <div
        class="relative overflow-hidden rounded-2xl border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800 dark:shadow-none">
        <!-- Brand accent line -->
        <div class="absolute inset-x-0 top-0 h-1 bg-brand-500"></div>

        <!-- Status indicator -->
        <div class="mb-6 flex items-center gap-3">
          <div
            class="flex size-10 items-center justify-center rounded-full bg-brand-500/10">
            <OIcon
              collection="heroicons"
              name="shield-check"
              class="size-5 text-brand-500" />
          </div>
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white/90">
              {{ t('web.homepage.this_is_a_private_instance_only_authorized_team_') }}
            </p>
          </div>
        </div>

        <!-- Feature pills -->
        <div class="flex flex-wrap gap-3">
          <div
            class="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-gray-50 px-4 py-2 dark:border-white/10 dark:bg-white/5">
            <OIcon
              collection="heroicons"
              name="lock-closed"
              class="size-4 text-gray-500 dark:text-white/60" />
            <span class="text-sm text-gray-600 dark:text-white/70">
              {{ t('web.secrets.secure_encrypted_storage') }}
            </span>
          </div>
          <div
            class="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-gray-50 px-4 py-2 dark:border-white/10 dark:bg-white/5">
            <OIcon
              collection="heroicons"
              name="clock"
              class="size-4 text-gray-500 dark:text-white/60" />
            <span class="text-sm text-gray-600 dark:text-white/70">
              {{ t('web.secrets.auto_expire_after_viewing') }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
