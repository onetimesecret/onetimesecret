<script setup lang="ts">
  import { ref } from 'vue';

  interface Props {
    disabled: boolean;
    withAsterisk: boolean;
    primaryColor: string;
  }

  defineEmits<{
    (e: 'click'): void;  // Simplify - we don't need the event
  }>();

  const props = defineProps<Props>();

  const buttonColor = ref(props.primaryColor ?? '#dc4a22');
  </script>

  <template>
    <button
      type="submit"
      :style="{ backgroundColor: buttonColor }"
      class="grow rounded px-4 py-2 text-xl font-bold text-white transition-all duration-200 ease-in-out hover:scale-105 hover:bg-orange-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
      :disabled="disabled"
      :aria-label="$t('web.COMMON.button_create_secret')"
      @click.prevent="$emit('click')"
      name="kind"
      value="conceal">
      {{ $t('web.COMMON.button_create_secret') }}<span v-if="withAsterisk">*</span>
    </button>
  </template>
