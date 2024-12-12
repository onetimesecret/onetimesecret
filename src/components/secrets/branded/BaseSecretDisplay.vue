<!-- src/components/secrets/BaseSecretDisplay.vue -->
<script setup lang="ts">
  import { BrandSettings } from '@/schemas/models';
  import { Icon } from '@iconify/vue';
  import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';

  const props = defineProps<{
    instructions?: string;
    defaultTitle?: string;
    domainBranding: BrandSettings;
  }>();

  // Text expansion logic
  const textRef = ref<HTMLElement | null>(null);
  const isExpanded = ref(false);
  const isLongText = ref(false);

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

  const cornerClass = computed(() => {
    switch (props.domainBranding.corner_style) {
      case 'rounded':
        return 'rounded-md'; // Updated to 'rounded-md' for a more subtle rounding
      case 'pill':
        return 'rounded-xl'; // Updated to 'rounded-xl' for a more subtle rounding
      case 'square':
        return 'rounded-none';
      default:
        return '';
    }
  });

  const fontFamilyClass = computed(() => {
    switch (props.domainBranding.font_family) {
      case 'sans':
        return 'font-sans';
      case 'serif':
        return 'font-serif';
      case 'mono':
        return 'font-mono';
      default:
        return '';
    }
  });
</script>

<template>
  <div class="w-full rounded-lg bg-white p-4 dark:bg-gray-800 sm:p-6">
    <div class="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
      <!-- Logo slot -->
      <slot name="logo"></slot>

      <!-- Title and Instructions -->
      <div class="flex-1 text-center sm:text-left">
        <div class="relative min-h-[5.5rem] sm:min-h-24">
          <h2
            class="mb-2 text-base font-medium leading-normal text-gray-900 dark:text-gray-200 sm:mb-3 sm:text-xl"
            :class="{
              [fontFamilyClass]: true,
            }">
            <slot name="title">
              {{ defaultTitle }}
            </slot>
          </h2>

          <div class="relative">
            <p
              ref="textRef"
              class="pb-4"
              :class="[textClasses, fontFamilyClass]">
              {{ instructions || $t('web.shared.pre_reveal_default') }}
            </p>

            <button
              v-if="isLongText"
              @click="toggleExpand"
              class="absolute bottom-0 left-1/2 -translate-x-1/2 rounded-full border border-gray-200 bg-white px-3 py-1 text-xs text-gray-500 shadow-sm transition-all duration-200 hover:text-gray-700 hover:shadow dark:border-gray-600 dark:bg-gray-800 dark:text-gray-400 dark:hover:text-gray-300">
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
        class="flex min-h-32 w-full items-center justify-center bg-gray-100 dark:bg-gray-700 sm:min-h-36"
        :class="{
          [cornerClass]: true,
        }">
        <slot name="content"></slot>
      </div>
    </div>

    <!-- Action Button -->
    <slot name="action-button"></slot>

    <!-- Footer -->
    <div class="mt-4 flex items-baseline justify-between p-3 sm:p-4">
      <slot name="footer">
        <p class="flex items-center text-xs italic text-gray-400 dark:text-gray-500 sm:text-sm">
          <Icon
            icon="mdi:information"
            class="mr-1 size-4"
          />
          {{ $t('web.COMMON.careful_only_see_once') }}
        </p>
      </slot>
    </div>
  </div>
</template>
