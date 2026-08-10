<!-- src/apps/secret/conceal/BrandedHomepage.vue -->

<script setup lang="ts">
  import BrandedHero from '@/apps/secret/components/branded/BrandedHero.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import IncomingSecretFormBody from '@/apps/secret/components/incoming/IncomingSecretFormBody.vue';
  import DisabledHomepage from '@/apps/secret/views/DisabledHomepage.vue';
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
    fontFamilyClass,
    buttonTextLight,
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
  // Any such failure degrades to the same private disabled-homepage view an
  // anonymous visitor would otherwise see — they must never be shown
  // upgrade/billing or misconfiguration copy on the branded front door.
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
        // Degrade to the disabled-homepage view; the store captures error state.
      } finally {
        incomingLoading.value = false;
      }
    },
    { immediate: true }
  );

  const showIncomingForm = computed(
    () => incomingMode.value && !incomingLoading.value && incomingAvailable.value
  );
  // The private front door: the homepage is not public, or incoming mode was
  // active but degraded at runtime. Presentation is delegated to the
  // disabled-homepage variant dispatcher (DisabledHomepage.vue), which is
  // brand-aware and honours the per-domain / deployment-wide variant defaults.
  const showDisabledHomepage = computed(
    () =>
      !allowPublicHomepage.value ||
      (incomingMode.value && !incomingLoading.value && !incomingAvailable.value)
  );

  // Send-a-secret copy only while the incoming form is (or is about to be)
  // the content below it. Once the runtime check degrades incoming to the
  // disabled-homepage view, fall back to the neutral copy the create branch
  // shows — a "Send a secret" headline over a members-only notice reads as
  // a broken page.
  const incomingCopy = computed(
    () => incomingMode.value && (incomingLoading.value || incomingAvailable.value)
  );
  const headline = computed(() =>
    incomingCopy.value ? t('web.homepage.send_a_secret') : t('web.homepage.create_a_secure_link')
  );
  const subline = computed(() =>
    incomingCopy.value
      ? t('web.homepage.deliver_sensitive_information_directly_and_securely')
      : t('web.homepage.send_sensitive_information_that_can_only_be_viewed_once')
  );
</script>

<template>
  <!--
    Custom Domain Homepage (branded landing for self-hosted workspaces)

    Audiences:
    - Recipients arriving via a shared link
    - Team members who need to sign in (via TransactionalHeader)
    - Admins verifying the branded landing page

    BrandedHomepage owns the public-vs-private decision
    (allowPublicHomepage + the runtime incoming-degradation guard) and
    delegates presentation:
    - Public create mode: branded hero + secret creation form
    - Public incoming mode (secrets_mode=incoming): branded hero + incoming
      secrets form; degrades to the disabled-homepage view below if incoming
      becomes unavailable at runtime
    - Private mode: hands off to the disabled-homepage variant dispatcher,
      which renders the operator-selected variant (closed / minimal / v1)
      with full brand awareness
  -->
  <div class="w-full">
    <!--
      Private (or incoming unavailable): delegate to the disabled-homepage
      variant dispatcher. It is brand-aware via useDisabledConfig and honours
      the per-domain homepage_config.disabled_homepage_variant plus the
      deployment-wide DEFAULT_CUSTOM_DOMAIN_DISABLED_HOMEPAGE_VARIANT default.
      The variant owns its own hero, so BrandedHero is suppressed here.
    -->
    <DisabledHomepage v-if="showDisabledHomepage" />

    <!-- Public create/incoming mode: branded hero over the active form -->
    <div
      v-else
      :class="fontFamilyClass"
      class="relative mx-auto w-full max-w-xl px-4">
      <BrandedHero
        class="mb-8"
        :title="headline"
        :subtitle="subline" />

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
    </div>
  </div>
</template>
