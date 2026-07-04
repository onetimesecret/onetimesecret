<!-- src/apps/workspace/components/domains/DomainHomepageSelector.vue -->

<script setup lang="ts">
/**
 * Domain Homepage Experience Selector
 *
 * Radio-card group choosing what anonymous visitors get on the domain
 * homepage: a private landing page (no interactive form), the classic
 * secret-creation form, or the incoming-secrets form.
 *
 * The backend stores this as two fields with merge semantics —
 * `enabled` (any interactive functionality at all) plus `secrets_mode`
 * (which kind) — but operators think in terms of one three-way choice,
 * so the UI presents exactly that.
 *
 * The incoming option is gated: hidden when the deployment disables
 * incoming secrets, locked behind the plan entitlement, and disabled
 * until the domain's incoming config is ready (enabled with at least one
 * recipient) — selecting it would otherwise create a homepage with
 * nowhere to deliver. The backend enforces the same rule on write.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import type { RouteLocationRaw } from 'vue-router';
import OIcon from '@/shared/components/icons/OIcon.vue';

export type HomepageChoice = 'private' | 'create' | 'incoming';

interface Option {
  key: HomepageChoice;
  icon: string;
  titleKey: string;
  descriptionKey: string;
}

interface Props {
  modelValue: HomepageChoice;
  /** Disable the whole group (save in flight, insufficient role). */
  disabled?: boolean;
  /** Whether the incoming option is offered at all (deployment flag + entitlement). */
  incomingAvailable?: boolean;
  /** Whether incoming can be selected (enabled with >= 1 recipient). */
  incomingReady?: boolean;
  /** Route to the incoming recipients configuration page. */
  incomingConfigRoute: RouteLocationRaw;
}

const props = withDefaults(defineProps<Props>(), {
  disabled: false,
  incomingAvailable: false,
  incomingReady: false,
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: HomepageChoice): void;
}>();

const { t } = useI18n();

const options = computed<Option[]>(() => {
  const base: Option[] = [
    {
      key: 'private',
      icon: 'shield-check',
      titleKey: 'web.domains.homepage.option_private_title',
      descriptionKey: 'web.domains.homepage.option_private_description',
    },
    {
      key: 'create',
      icon: 'pencil-square',
      titleKey: 'web.domains.homepage.option_create_title',
      descriptionKey: 'web.domains.homepage.option_create_description',
    },
  ];
  if (props.incomingAvailable) {
    base.push({
      key: 'incoming',
      icon: 'inbox-arrow-down',
      titleKey: 'web.domains.homepage.option_incoming_title',
      descriptionKey: 'web.domains.homepage.option_incoming_description',
    });
  }
  return base;
});

const isOptionDisabled = (key: HomepageChoice): boolean => {
  if (props.disabled) return true;
  if (key === 'incoming') return !props.incomingReady;
  return false;
};

const select = (key: HomepageChoice) => {
  if (isOptionDisabled(key) || key === props.modelValue) return;
  emit('update:modelValue', key);
};

// Shared by the tab stop and keyboard nav below so neither re-filters
// `options` on every render/keypress.
const enabledOptions = computed(() => options.value.filter((o) => !isOptionDisabled(o.key)));

// Roving tabindex: the selected option is the tab stop; arrows move
// selection between enabled options (standard radiogroup keyboard model).
// When the current selection is disabled or hidden (stored mode 'incoming'
// while incoming is unready, or the option gated away entirely), the first
// enabled option takes the tab stop so the group stays keyboard-reachable.
const tabStopKey = computed<HomepageChoice | null>(() => {
  const selected = options.value.find((o) => o.key === props.modelValue);
  if (selected && !isOptionDisabled(selected.key)) return selected.key;
  return enabledOptions.value[0]?.key ?? null;
});

const optionTabindex = (key: HomepageChoice) => (key === tabStopKey.value ? 0 : -1);

const onKeydown = (event: KeyboardEvent) => {
  const keys = ['ArrowDown', 'ArrowRight', 'ArrowUp', 'ArrowLeft'];
  if (!keys.includes(event.key)) return;
  event.preventDefault();

  const enabled = enabledOptions.value;
  if (enabled.length === 0) return;

  // Reference point for directional movement: the selection when it is
  // enabled, otherwise the tab-stop option (a disabled/hidden selection is
  // not in `enabled`, and -1 index math would land both arrows on the same
  // option).
  const referenceKey = enabled.some((o) => o.key === props.modelValue)
    ? props.modelValue
    : tabStopKey.value;
  const currentIdx = enabled.findIndex((o) => o.key === referenceKey);
  const delta = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : -1;
  const nextIdx = (currentIdx + delta + enabled.length) % enabled.length;
  select(enabled[nextIdx].key);
};
</script>

<template>
  <div
    role="radiogroup"
    :aria-label="t('web.domains.homepage.title')"
    class="space-y-2"
    @keydown="onKeydown">
    <div
      v-for="option in options"
      :key="option.key">
      <button
        type="button"
        role="radio"
        :aria-checked="option.key === modelValue"
        :tabindex="optionTabindex(option.key)"
        :disabled="isOptionDisabled(option.key)"
        :data-testid="`homepage-option-${option.key}`"
        :class="[
          'flex w-full items-start gap-3 rounded-lg border p-3 text-left transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500',
          option.key === modelValue
            ? 'border-brand-500 bg-brand-50/50 dark:border-brand-400 dark:bg-brand-900/10'
            : 'border-gray-200 dark:border-gray-700',
          isOptionDisabled(option.key)
            ? 'cursor-not-allowed opacity-60'
            : option.key !== modelValue
              ? 'hover:border-gray-300 hover:bg-gray-50 dark:hover:border-gray-600 dark:hover:bg-gray-700/30'
              : '',
        ]"
        @click="select(option.key)">
        <!-- Radio indicator -->
        <span
          :class="[
            'mt-0.5 flex size-4 shrink-0 items-center justify-center rounded-full border',
            option.key === modelValue
              ? 'border-brand-500 dark:border-brand-400'
              : 'border-gray-300 dark:border-gray-600',
          ]"
          aria-hidden="true">
          <span
            v-if="option.key === modelValue"
            class="size-2 rounded-full bg-brand-500 dark:bg-brand-400"></span>
        </span>

        <span class="min-w-0 flex-1">
          <span class="flex items-center gap-2">
            <OIcon
              collection="heroicons"
              :name="option.icon"
              class="size-4 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <span class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t(option.titleKey) }}
            </span>
          </span>
          <span class="mt-0.5 block text-xs text-gray-500 dark:text-gray-400">
            {{ t(option.descriptionKey) }}
          </span>
        </span>
      </button>

      <!-- Unready incoming: explain the gate and link to the fix -->
      <div
        v-if="option.key === 'incoming' && !incomingReady"
        class="mt-1 flex flex-wrap items-center gap-x-2 pl-7 text-xs text-amber-600 dark:text-amber-400"
        data-testid="homepage-incoming-unready-hint">
        <span>{{ t('web.domains.homepage.incoming_requires_recipients') }}</span>
        <RouterLink
          :to="incomingConfigRoute"
          class="inline-flex items-center gap-0.5 font-medium underline-offset-2 hover:underline">
          {{ t('web.domains.homepage.configure_recipients') }}
          <OIcon
            collection="heroicons"
            name="arrow-right"
            class="size-3"
            aria-hidden="true" />
        </RouterLink>
      </div>
    </div>
  </div>
</template>
