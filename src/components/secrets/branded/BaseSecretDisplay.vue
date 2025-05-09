<!-- src/components/secrets/BaseSecretDisplay.vue -->

<script setup lang="ts">
  /**
   * Core display component for branded secret workflows that provides consistent
   * layout and styling across both confirmation and reveal states.
   *
   * This component is specifically designed for custom branded deployments where
   * maintaining brand consistency is prioritized over marketing opportunities.
   * For the core Onetime Secret implementation, see the canonical SecretDisplayCase.
   *
   * @prop defaultTitle - Fallback title when branding is unavailable
   * @prop instructions - Optional pre-reveal instructions from domain branding
   * @prop domainBranding - Domain-specific styling configuration
   *
   * @slot logo - Domain logo or fallback icon
   * @slot content - Main content area (confirmation form or secret content)
   * @slot action-button - Action button slot (submit or copy)
   */
  import OIcon from '@/components/icons/OIcon.vue';
  import { BrandSettings } from '@/schemas/models';
  import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
  import { Composer, useI18n } from 'vue-i18n';
  const i18n = useI18n();

  const props = defineProps<{
    domainBranding: BrandSettings;
    cornerClass: string;
    fontClass: string;
    defaultTitle?: string;
    previewI18n?: Composer;
    isRevealed?: boolean;
  }>();

  // Text expansion logic
  const textRef = ref<HTMLElement | null>(null);
  const isExpanded = ref(false);
  const isLongText = ref(false);

  const displayComposer = props.previewI18n || i18n;

  // Computed property for instructions text
  const instructions = computed(() => {
    const isPostReveal = props.isRevealed === true;
    const instructionsKey = isPostReveal
      ? 'instructions_post_reveal'
      : 'instructions_pre_reveal';
    const defaultKey = isPostReveal
      ? 'web.shared.post_reveal_default'
      : 'web.shared.pre_reveal_default';

    return props.domainBranding[instructionsKey]?.trim() ||
           displayComposer.t(defaultKey);
  });

  // Reusable computed properties
  const textClasses = computed(() => ({
    'text-gray-600 dark:text-gray-400 text-xs sm:text-sm leading-relaxed': true,
    'line-clamp-6': !isExpanded.value,
    'pb-6': isLongText.value && !isExpanded.value,
  }));

  // Text length checking
  const checkTextLength = () => {
    nextTick(() => {
      const element = textRef.value;
      if (element) {
        element.classList.remove('line-clamp-6');
        const lineHeight = parseInt(window.getComputedStyle(element).lineHeight);
        isLongText.value = element.scrollHeight > lineHeight * 4;
        if (!isExpanded.value) {
          element.classList.add('line-clamp-6');
        }
      }
    });
  };

  onMounted(() => {
    checkTextLength();
    window.addEventListener('resize', checkTextLength);
  });

  onUnmounted(() => {
    window.removeEventListener('resize', checkTextLength);
  });

  const toggleExpand = () => {
    isExpanded.value = !isExpanded.value;
  };
</script>

<template>
  <div class="min-h-[35vh] w-full rounded-lg bg-white p-4 dark:bg-gray-800 sm:p-6">
    <!-- Title and Instructions -->
    <div class="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
      <slot name="logo"></slot>

      <div class="flex-1 text-center sm:text-left">
        <div class="relative min-h-[5.5rem] sm:min-h-24">
          <h2
            :class="[cornerClass, fontClass]"
            class="mb-2 text-base font-medium leading-normal
              text-gray-900 dark:text-gray-200 sm:mb-3 sm:text-xl">
            <slot name="title">{{ defaultTitle }}</slot>
          </h2>

          <div class="relative">
            <p
              ref="textRef"
              :class="[textClasses, cornerClass, fontClass]"
              class="pb-4">
              {{ instructions || displayComposer.t('web.shared.pre_reveal_default') }}
            </p>

            <button
              v-if="isLongText"
              @click="toggleExpand"
              :class="[textClasses, cornerClass, fontClass]"
              class="absolute bottom-0 left-1/2 -translate-x-1/2
                border border-gray-200 bg-white px-3 py-1
                text-xs text-gray-500 shadow-sm transition-all
                duration-200 hover:text-gray-700 hover:shadow
                dark:border-gray-600 dark:bg-gray-800 dark:text-gray-400 dark:hover:text-gray-300">
              <slot
                name="expand-button"
                :is-expanded="isExpanded">
                {{ isExpanded ? 'Show Less' : 'Show More' }}
              </slot>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Content Area -->
    <div class="my-3 sm:my-4">
      <div
        :class="[cornerClass]"
        class="flex min-h-32 w-full items-center justify-center
          bg-gray-100 dark:bg-gray-700 sm:min-h-36">
        <slot name="content"></slot>
      </div>
    </div>

    <!-- Action Button -->
    <slot name="action-button"></slot>

    <!-- Footer -->
    <div class="mt-4 flex items-baseline justify-between p-3 sm:p-4">
      <slot name="footer">
        <p class="flex items-center text-xs italic text-gray-400 dark:text-gray-500 sm:text-sm">
          <OIcon
            collection="mdi"
            name="information"
            class="mr-1 size-4"
          />
          {{ displayComposer.t('web.COMMON.careful_only_see_once') }}
        </p>
      </slot>
    </div>
  </div>
</template>
