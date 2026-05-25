<!-- src/apps/secret/conceal/AccessDenied.vue -->

<script setup lang="ts">
  import MonotoneJapaneseSecretButtonIcon from '@/shared/components/icons/MonotoneJapaneseSecretButtonIcon.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { storeToRefs } from 'pinia';
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /*
    Purpose: Disabled-homepage view shown when UI is enabled but the homepage
    secret form is gated behind authentication (auth required or external mode).

    Renders two visual modes off the same component:
    - Branded: configured custom domain — uses the workspace logo (or a
      monogram derived from the brand description) + brand color accents,
      and a contextual headline naming the workspace.
    - Unbranded: canonical site, or a custom domain on a free plan with no
      branding configured — uses the OTS mark and surfaces a subtle promo
      that free plans now include custom domains.

    Audiences:
    - Recipients who arrived via a shared link and may be curious
    - Team members who need to sign in
    - Admins verifying the gated landing page
  */

  const { t } = useI18n();

  const identityStore = useProductIdentity();
  const { isCustom, primaryColor, logoUri, displayName, displayDomain, brand } =
    storeToRefs(identityStore);

  const bootstrapStore = useBootstrapStore();
  const { authentication } = storeToRefs(bootstrapStore);

  // "Branded" means a custom domain has actually been configured with a brand
  // description — distinct from `isCustom`, which can be true even when no
  // branding is set (free tier with a custom domain).
  const isBranded = computed(() => isCustom.value && !!brand.value?.description);

  const workspaceName = computed(
    () => brand.value?.description?.trim() || displayName.value
  );

  const monogramInitial = computed(() =>
    (workspaceName.value || displayDomain.value || 'A').trim().charAt(0).toUpperCase()
  );

  // Apex form of the displayed domain (e.g. "secrets.acme.co" -> "acme.co"),
  // used in the subtitle copy without the secrets-subdomain prefix.
  const apexDomain = computed(() =>
    (displayDomain.value || '').replace(/^[a-z0-9-]+\.(?=[^.]+\.[^.]+$)/i, '')
  );

  const subtitleCopy = computed(() =>
    isBranded.value
      ? t('web.homepage.disabled_access.team_subtitle', { domain: apexDomain.value })
      : t('web.homepage.disabled_access.public_subtitle')
  );

  const showSignin = computed(() => authentication.value?.signin !== false);
  const showPromo = computed(() => !isBranded.value);

  // Image error handling for branded logos that may 404
  const logoError = ref(false);
  const onLogoError = () => {
    logoError.value = true;
  };
  const hasUsableLogo = computed(() => !!logoUri.value && !logoError.value);

  // Inline style binders for brand-color accents (used only in branded mode)
  const monogramStyle = computed(() => ({ backgroundColor: primaryColor.value }));
  const dotStyle = computed(() =>
    isBranded.value
      ? { backgroundColor: primaryColor.value, boxShadow: `0 0 8px ${primaryColor.value}` }
      : {}
  );
</script>

<template>
  <div class="relative mx-auto flex w-full max-w-2xl flex-col items-center px-4 pb-12 pt-16 text-center sm:pt-24">
    <!-- Mark: branded logo, branded monogram fallback, or OTS mark -->
    <div class="mb-8 flex items-center justify-center">
      <img
        v-if="isBranded && hasUsableLogo"
        :src="logoUri ?? ''"
        :alt="workspaceName"
        class="h-24 w-auto max-w-[180px] object-contain"
        @error="onLogoError" />
      <div
        v-else-if="isBranded"
        :style="monogramStyle"
        class="flex size-28 items-center justify-center rounded-3xl font-brand text-6xl font-extrabold tracking-tight text-white shadow-sm"
        aria-hidden="true">
        {{ monogramInitial }}
      </div>
      <div
        v-else
        class="flex size-28 items-center justify-center rounded-3xl bg-brand-500 text-white shadow-sm dark:bg-brand-600"
        aria-hidden="true">
        <MonotoneJapaneseSecretButtonIcon
          :size="76"
          class="text-white" />
      </div>
    </div>

    <!-- Eyebrow badge -->
    <span
      class="inline-flex items-center gap-2 text-xs font-bold uppercase tracking-[0.15em] text-brand-700 dark:text-brand-400">
      <span
        class="size-[7px] rounded-full bg-brand-500 shadow-[0_0_8px_var(--tw-shadow-color)] shadow-brand-500"
        :style="dotStyle"
        aria-hidden="true"></span>
      <template v-if="isBranded">
        {{ t('web.homepage.disabled_access.private_instance_eyebrow') }}
      </template>
      <template v-else>
        {{ t('web.homepage.disabled_access.members_only_eyebrow') }}
      </template>
    </span>

    <!-- Headline -->
    <h1
      class="mt-5 max-w-2xl font-brand text-4xl font-extrabold leading-[1.05] tracking-tight text-gray-900 dark:text-white sm:text-5xl"
      style="text-wrap: balance">
      <i18n-t
        v-if="isBranded"
        keypath="web.homepage.disabled_access.team_link_headline"
        tag="span"
        scope="global">
        <template #workspace>
          <em class="font-bold italic">{{ workspaceName }}</em>
        </template>
      </i18n-t>
      <template v-else>
        {{ t('web.homepage.disabled_access.signin_headline_prefix') }}
        <em class="font-bold italic">{{
          t('web.homepage.disabled_access.signin_headline_emphasis')
        }}</em>
      </template>
    </h1>

    <!-- Subtitle -->
    <p
      class="mt-5 max-w-xl text-base leading-relaxed text-gray-600 dark:text-gray-300 sm:text-lg"
      style="text-wrap: pretty">
      {{ subtitleCopy }}
    </p>

    <!-- CTA row -->
    <div class="mt-9 inline-flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
      <router-link
        v-if="showSignin"
        to="/signin"
        data-testid="disabled-homepage-signin"
        class="inline-flex items-center gap-2 rounded-xl bg-brand-600 px-7 py-3.5 font-sans text-[15px] font-semibold text-white shadow-sm transition-colors hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900">
        {{ t('web.homepage.disabled_access.signin_cta') }}
        <OIcon
          collection="heroicons"
          name="arrow-right"
          class="size-4" />
      </router-link>
      <a
        href="https://onetimesecret.com/"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1.5 text-sm font-semibold text-gray-500 transition-colors hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
        <OIcon
          collection="heroicons"
          name="information-circle"
          class="size-4" />
        {{ t('web.homepage.disabled_access.what_is_this') }}
      </a>
    </div>

    <!-- Trust strip -->
    <div class="mt-12 w-full max-w-xl border-t border-gray-200 pt-6 dark:border-gray-700">
      <div class="flex flex-wrap items-center justify-center gap-x-7 gap-y-3">
        <span class="inline-flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="lock-closed"
            class="size-4 text-gray-600 dark:text-gray-300" />
          {{ t('web.homepage.disabled_access.trust_encrypted') }}
        </span>
        <span class="inline-flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="eye"
            class="size-4 text-gray-600 dark:text-gray-300" />
          {{ t('web.homepage.disabled_access.trust_viewed_once') }}
        </span>
        <span class="inline-flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="server-stack"
            class="size-4 text-gray-600 dark:text-gray-300" />
          {{ t('web.homepage.disabled_access.trust_zero_retained') }}
        </span>
      </div>
    </div>

    <!-- Promo (unbranded / free-tier only) -->
    <div
      v-if="showPromo"
      class="mt-6 inline-flex max-w-xl items-center gap-3 rounded-2xl border border-dashed border-gray-300 bg-gray-50 px-4 py-3 text-left dark:border-gray-700 dark:bg-gray-800/40">
      <span
        class="inline-flex size-9 flex-shrink-0 items-center justify-center rounded-lg border border-brandcomp-500/30 bg-brandcomp-500/10 text-brandcomp-600 dark:text-brandcomp-400">
        <OIcon
          collection="heroicons"
          name="sparkles"
          class="size-5" />
      </span>
      <div class="text-sm leading-snug">
        <div class="font-semibold text-gray-900 dark:text-white">
          {{ t('web.homepage.disabled_access.promo_title') }}
        </div>
        <div class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.homepage.disabled_access.promo_subtitle') }}
          <a
            href="https://onetimesecret.com/plans"
            target="_blank"
            rel="noopener noreferrer"
            class="ml-1 font-semibold text-brand-700 hover:underline dark:text-brand-400">
            {{ t('web.homepage.disabled_access.promo_learn_how') }} &rarr;
          </a>
        </div>
      </div>
    </div>
  </div>
</template>
