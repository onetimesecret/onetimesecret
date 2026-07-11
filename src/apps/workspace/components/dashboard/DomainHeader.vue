<!-- src/apps/workspace/components/dashboard/DomainHeader.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useDomainStatus } from '@/shared/composables/useDomainStatus';
  import { isApproximatedDomainValidation } from '@/utils/features';
  import { CustomDomain } from '@/schemas/shapes/v3';
  import { computed } from 'vue';

  const { t } = useI18n();

  const props = withDefaults(
    defineProps<{
      domain: CustomDomain | null;
      hasUnsavedChanges: boolean;
      orgid: string;
      /** Optional path appended to domain URL for external link (e.g., '/incoming') */
      externalPath?: string;
      /**
       * Opt-in Back link rendered on the left of the title row (before the
       * domain name), so Back + title + Save share one row. Hidden by default;
       * a page turns it on with `back-visible` and handles routing via `@back`.
       */
      backVisible?: boolean;
      backLabel?: string;
      /**
       * Opt-in Save action rendered inline with the domain title (right side of
       * the title row). Hidden by default so the 7 other consumers are
       * unaffected; a page turns it on with `save-visible` and listens for
       * `@save`. Keeps the save affordance in one place instead of a separate
       * action bar per page.
       */
      saveVisible?: boolean;
      saveDisabled?: boolean;
      saveLoading?: boolean;
      saveLabel?: string;
      savingLabel?: string;
    }>(),
    {
      externalPath: '',
      backVisible: false,
      backLabel: 'web.COMMON.back',
      saveVisible: false,
      saveDisabled: false,
      saveLoading: false,
      saveLabel: 'web.LABELS.update',
      savingLabel: 'web.LABELS.updating',
    }
  );

  const emit = defineEmits<{
    (e: 'save'): void;
    (e: 'back'): void;
  }>();

  // Optional chaining on domain is defensive: the only consumer
  // (<RouterLink :to="verifyRoute">) lives inside v-if="domain", so the
  // computed is never read while domain is null. The ?. keeps the type
  // narrow without forcing a non-null assertion that would lie about the
  // prop contract (domain is CustomDomain | null).
  const verifyRoute = computed(() => `/org/${props.orgid}/domains/${props.domain?.extid}/verify`);

  const { statusIcon, statusColor, displayStatus } = useDomainStatus(
    () => props.domain
  );

  // The active/inactive badge reflects Approximated's per-domain DNS check.
  // On installs that don't use Approximated, that status is never populated
  // (every domain would read "Inactive"), so hide the badge entirely. See #3618
  // rationale in isApproximatedDomainValidation().
  const showVerificationStatus = computed(() => isApproximatedDomainValidation());

</script>

<template>
  <div class="border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
    <div class="mx-auto max-w-7xl p-4 sm:px-6 lg:px-8">
      <!-- Title section - make text smaller on mobile -->
      <div
        v-if="domain"
        class="flex flex-col">
        <div class="flex items-center justify-between gap-2">
          <div class="flex min-w-0 items-center gap-4">
            <button
              v-if="backVisible"
              type="button"
              class="inline-flex shrink-0 items-center gap-1.5 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              @click="emit('back')">
              <OIcon
                collection="heroicons"
                name="arrow-left"
                class="size-5"
                aria-hidden="true" />
              {{ t(backLabel) }}
            </button>
            <!-- prettier-ignore-attribute class -->
            <h1
              class="mb-0 flex min-w-0 items-center truncate text-2xl font-bold
                leading-tight text-gray-900 dark:text-white sm:text-3xl">
              <span class="truncate">{{ domain.display_domain }}</span>
              <!-- prettier-ignore-attribute class -->
              <a
                :href="`https://${domain.display_domain}${externalPath}`"
                target="_blank"
                rel="noopener noreferrer"
                class="ml-1 inline-flex shrink-0 items-center rounded p-1
                  text-gray-400 transition-colors hover:text-gray-600
                  focus-visible:outline-none focus-visible:ring-2
                  focus-visible:ring-brand-500 dark:text-gray-500
                  dark:hover:text-gray-300"
                :title="t('web.domains.open_domain_in_new_tab')">
                <OIcon
                  collection="mdi"
                  name="open-in-new"
                  class="size-5" />
              </a>
            </h1>
          </div>
          <div class="flex shrink-0 items-center gap-3">
            <slot>
              <!-- prettier-ignore-attribute class -->
              <div
                v-if="showVerificationStatus"
                class="inline-flex h-10 items-center rounded-md bg-gray-100 px-3
                  dark:bg-gray-700">
                <RouterLink
                  :to="verifyRoute"
                  class="inline-flex items-center gap-1.5"
                  :data-tooltip="t('web.domains.view_domain_verification_status')">
                  <OIcon
                    collection="mdi"
                    :name="statusIcon"
                    class="size-4 shrink-0"
                    :class="statusColor" />
                  <span class="font-brand text-sm leading-none">{{ displayStatus }}</span>
                </RouterLink>
              </div>
            </slot>

            <!-- prettier-ignore-attribute class -->
            <button
              v-if="saveVisible"
              type="button"
              :disabled="saveDisabled"
              @click="emit('save')"
              class="inline-flex h-10 min-w-[110px] shrink-0 items-center
                justify-center rounded-lg border border-transparent
                bg-brand-600 px-4 text-sm font-medium text-white shadow-sm
                transition-all duration-200 hover:bg-brand-700 focus:ring-2
                focus:ring-brand-500 focus:ring-offset-2 focus:outline-none
                disabled:cursor-not-allowed disabled:opacity-50
                dark:focus:ring-brand-400 dark:focus:ring-offset-0">
              <OIcon
                v-if="saveLoading"
                collection="mdi"
                name="loading"
                class="mr-2 -ml-1 size-4 animate-spin motion-reduce:animate-none" />
              <OIcon
                v-else
                collection="mdi"
                name="content-save"
                class="mr-2 -ml-1 size-4" />
              {{ saveLoading ? t(savingLabel) : t(saveLabel) }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-else
        class="flex flex-col gap-1">
        <!-- Loading placeholder -->
        <div class="h-8 w-64 animate-pulse motion-reduce:animate-none rounded bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-4 w-24 animate-pulse motion-reduce:animate-none rounded bg-gray-200 dark:bg-gray-700"></div>
      </div>
    </div>
  </div>
</template>
