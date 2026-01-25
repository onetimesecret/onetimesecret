<!-- src/apps/secret/conceal/BrandedHomepage.vue -->

<script setup lang="ts">
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useProductIdentity } from '@/shared/stores/identityStore';

  const { t } = useI18n();

  const {
    allowPublicHomepage,
    primaryColor,
    cornerClass,
    buttonTextLight,
    logoUri,
    displayName,
  } = useProductIdentity();

  // Handle logo 404 errors gracefully
  const imageError = ref(false);
  const handleImageError = () => {
    imageError.value = true;
  };
</script>

<template>
  <div class="mx-auto w-full max-w-xl px-4">
    <!-- Logo + Taglines (since MastHead is disabled for custom domains) -->
    <div class="mb-8 text-center">
      <!-- Logo with error handling - hides if 404 -->
      <div v-if="logoUri && !imageError" class="mb-4 flex justify-center">
        <img
          :src="logoUri"
          class="h-16 max-w-[200px] object-contain"
          :alt="displayName"
          @error="handleImageError" />
      </div>
      <h1 class="text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.homepage.create_a_secure_link') }}
      </h1>
      <p class="mt-2 text-gray-600 dark:text-gray-300">
        {{ t('web.homepage.send_sensitive_information_that_can_only_be_viewed_once') }}
      </p>
    </div>

    <!-- Public homepage with secret form -->
    <SecretForm
      v-if="allowPublicHomepage"
      class="mb-8"
      :primary-color="primaryColor"
      :button-text-light="buttonTextLight"
      :corner-class="cornerClass"
      :with-recipient="false"
      :with-asterisk="false"
      :with-generate="false" />

    <!--
      Private Instance Landing

      Purpose: Landing page for custom domains with restricted access.

      Key audiences:
      - Recipients: People who received/viewed a secure message
      - Internal teams: Employees who need to know how to share sensitive info
      - Admins: People managing the service

      Design notes:
      - Professional, minimal appearance
      - Uses brand color as accent
      - Trust-focused messaging
    -->

    <div v-else class="space-y-8">
      <!-- Status Card -->
      <div
        class="relative overflow-hidden rounded-2xl border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800 dark:shadow-none">
        <!-- Brand accent line -->
        <div
          class="absolute inset-x-0 top-0 h-1"
          :style="{ backgroundColor: primaryColor }"></div>

        <!-- Status indicator -->
        <div class="mb-6 flex items-center gap-3">
          <div
            class="flex size-10 items-center justify-center rounded-full"
            :style="{ backgroundColor: `${primaryColor}20` }">
            <OIcon
              collection="heroicons"
              name="shield-check"
              class="size-5"
              :style="{ color: primaryColor }" />
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
