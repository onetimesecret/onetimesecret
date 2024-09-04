<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
// Importing altcha package will introduce a new element <altcha-widget>.
//
// See compilerOptions in vite.config.ts.
import 'altcha';


interface Props {
  payload?: string;
  isFloating?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  isFloating: true,
});

const emit = defineEmits<{
  (e: 'update:payload', value: string): void;
}>();

const altchaWidget = ref<HTMLElement | null>(null);
const internalValue = ref(props.payload);

watch(internalValue, (v) => {
  emit('update:payload', v || '');
});

const onStateChange = (ev: CustomEvent | Event) => {
  if ('detail' in ev) {
    const { payload, state } = ev.detail;

    if (state === 'verified' && payload) {
      internalValue.value = payload;
    } else {
      internalValue.value = '';
    }
  }
};

onMounted(() => {
  if (altchaWidget.value) {
    altchaWidget.value.addEventListener('statechange', onStateChange);
  }
});

onUnmounted(() => {
  if (altchaWidget.value) {
    altchaWidget.value.removeEventListener('statechange', onStateChange);
  }
});
</script>

<template>
  <!-- See docs: https://altcha.org/docs/website-integration/#using-altcha-widget -->
  <!-- https://altcha.org/docs/floating-ui/ -->
  <!-- https://altcha.org/docs/website-integration/ -->
  <div class="flex">
    <altcha-widget ref="altchaWidget"
                   challengeurl="/api/v2/altcha/challenge"
                   :floating="isFloating"
                   floatinganchor="bottom-right"
                   hidelogo
                   hidefooter
                   class="">

    </altcha-widget>
  </div>
</template>

<style scoped>
/* https://altcha.org/docs/widget-customization/ */
</style>
