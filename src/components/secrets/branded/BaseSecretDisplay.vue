<!-- src/components/secrets/BaseSecretDisplay.vue -->
<template>
  <div class="w-full bg-white dark:bg-gray-800 rounded-lg p-4 sm:p-6">
    <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 mb-6">
      <!-- Logo slot -->
      <slot name="logo"></slot>

      <!-- Title and Instructions -->
      <div class="flex-1 text-center sm:text-left">
        <div class="min-h-[5.5rem] sm:min-h-[6rem] relative">
          <h2 class="text-gray-900 dark:text-gray-200 text-base sm:text-lg font-medium mb-2 sm:mb-3 leading-normal"
              :style="{ fontFamily: domainBranding.font_family }">
            <slot name="title">{{ defaultTitle }}</slot>
          </h2>

          <div class="relative">
            <p ref="textRef"
               class="pb-4"
               :class="textClasses"
               :style="{ fontFamily: domainBranding.font_family }">
               {{ instructions || $t('web.shared.pre_reveal_default') }}
            </p>

            <button v-if="isLongText"
                    @click="toggleExpand"
                    class="absolute bottom-0 left-1/2 transform -translate-x-1/2 px-3 py-1 text-xs text-gray-500
                     dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300
                     bg-white dark:bg-gray-800 shadow-sm hover:shadow
                     rounded-full border border-gray-200 dark:border-gray-600
                     transition-all duration-200">
              <slot name="expand-button" :is-expanded="isExpanded">
                {{ isExpanded ? 'Show Less' : 'Show More' }}
              </slot>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Content Area -->
    <div class="mt-3 sm:mt-4 mb-3 sm:mb-4">
      <div class="w-full min-h-32 sm:min-h-36 bg-gray-100 dark:bg-gray-700 flex items-center justify-center p-4"
           :class="contentAreaClasses">
        <slot name="content"></slot>
      </div>
    </div>

    <!-- Action Button -->
    <slot name="action-button"></slot>

    <!-- Footer -->
    <div class="flex justify-between items-baseline p-3 sm:p-4 mt-4">
      <slot name="footer">
        <p class="text-xs sm:text-sm text-gray-500 dark:text-gray-400 italic flex items-center">
          <Icon icon="mdi:information" class="w-4 h-4 mr-1" />
          {{ $t('web.COMMON.careful_only_see_once') }}
        </p>
      </slot>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue';
import type { BrandSettings } from '@/types/onetime';
import { Icon } from '@iconify/vue';

const props = defineProps<{
  domainBranding: BrandSettings;
  instructions?: string;
  defaultTitle?: string;
}>();

// Text expansion logic
const textRef = ref<HTMLElement | null>(null);
const isExpanded = ref(false);
const isLongText = ref(false);

// Reusable computed properties
const textClasses = computed(() => ({
  'text-gray-600 dark:text-gray-400 text-xs sm:text-sm leading-relaxed': true,
  'line-clamp-6': !isExpanded.value,
  'pb-6': isLongText.value && !isExpanded.value
}));

const contentAreaClasses = computed(() => ({
  'rounded-lg': props.domainBranding.corner_style === 'rounded',
  'rounded-xl': props.domainBranding.corner_style === 'pill',
  'rounded-none': props.domainBranding.corner_style === 'square'
}));

// Text length checking
const checkTextLength = () => {
  nextTick(() => {
    const element = textRef.value;
    if (element) {
      element.classList.remove('line-clamp-6');
      const lineHeight = parseInt(window.getComputedStyle(element).lineHeight);
      isLongText.value = element.scrollHeight > (lineHeight * 4);
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
