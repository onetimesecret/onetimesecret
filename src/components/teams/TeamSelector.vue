<!-- src/components/teams/TeamSelector.vue -->

<script setup lang="ts">
import HoverTooltip from '@/components/common/HoverTooltip.vue';
import OIcon from '@/components/icons/OIcon.vue';
import { getRoleBadgeColor, getRoleLabel, type TeamWithRole } from '@/types/team';
import { useEventListener } from '@vueuse/core';
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const props = withDefaults(defineProps<{
  teams: TeamWithRole[];
  modelValue?: string;
  placeholder?: string;
}>(), {
  modelValue: '',
  placeholder: 'web.teams.select_team',
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const isOpen = ref(false);
const listboxRef = ref<HTMLElement | null>(null);

const selectedTeam = computed(() => props.teams.find((t) => t.id === props.modelValue));

const toggleOpen = () => {
  isOpen.value = !isOpen.value;
};

const close = () => {
  isOpen.value = false;
};

const handleTeamSelect = (teamId: string) => {
  emit('update:modelValue', teamId);
  close();
};

// Handle ESC key press
const handleEscPress = (e: KeyboardEvent) => {
  if (e.key === 'Escape' && isOpen.value) {
    close();
  }
};

onMounted(() => {
  document.addEventListener('keydown', handleEscPress);
});

onUnmounted(() => {
  document.removeEventListener('keydown', handleEscPress);
});

// Close on click outside
useEventListener(document, 'click', (e: MouseEvent) => {
  const target = e.target as HTMLElement;
  const modalEl = listboxRef.value?.closest('.relative');
  if (modalEl && !modalEl.contains(target) && isOpen.value) {
    close();
  }
}, { capture: true });

// Focus listbox when opening
watch(isOpen, (newValue) => {
  if (newValue && listboxRef.value) {
    nextTick(() => {
      listboxRef.value?.focus();
    });
  }
});

const getRoleBadge = (role: string) => ({
    color: getRoleBadgeColor(role as any),
    label: t(getRoleLabel(role as any)),
  });
</script>

<template>
  <div class="group relative">
    <HoverTooltip v-if="!selectedTeam">{{ t(placeholder) }}</HoverTooltip>
    <button
      type="button"
      @click="toggleOpen"
      class="group relative inline-flex h-11 w-full items-center justify-between gap-2 rounded-lg bg-white px-4 shadow-sm ring-1 ring-gray-200 transition-all duration-200 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800 dark:ring-gray-700 dark:hover:bg-gray-700 dark:focus:ring-brand-400 dark:focus:ring-offset-0"
      :aria-expanded="isOpen"
      :aria-label="selectedTeam ? selectedTeam.name : t(placeholder)"
      aria-haspopup="listbox"
    >
      <span v-if="selectedTeam" class="flex min-w-0 flex-1 items-center gap-2">
        <span class="truncate text-sm font-medium text-gray-900 dark:text-white">
          {{ selectedTeam.name }}
        </span>
        <span
          :class="[
            'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
            getRoleBadge(selectedTeam.current_user_role).color
          ]"
        >
          {{ getRoleBadge(selectedTeam.current_user_role).label }}
        </span>
      </span>
      <span v-else class="text-sm text-gray-500 dark:text-gray-400">
        {{ t(placeholder) }}
      </span>

      <OIcon
        collection="mdi"
        :name="isOpen ? 'chevron-up' : 'chevron-down'"
        class="size-5 shrink-0 text-gray-400"
        aria-hidden="true"
      />
    </button>

    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="transform scale-95 opacity-0"
      enter-to-class="transform scale-100 opacity-100"
      leave-active-class="transition duration-75 ease-in"
      leave-from-class="transform scale-100 opacity-100"
      leave-to-class="transform scale-95 opacity-0"
    >
      <div
        v-if="isOpen"
        ref="listboxRef"
        role="listbox"
        :aria-activedescendant="modelValue"
        tabindex="0"
        class="absolute left-0 right-0 z-50 mt-2 rounded-lg bg-white shadow-lg ring-1 ring-black/5 dark:bg-gray-800"
      >
        <div class="max-h-60 overflow-y-auto py-1">
          <button
            type="button"
            v-for="team in teams"
            :key="team.id"
            role="option"
            :aria-selected="modelValue === team.id"
            :class="[
              'flex w-full items-center justify-between gap-2',
              'px-4 py-3 text-left transition-colors',
              'text-gray-900 dark:text-gray-100',
              'hover:bg-gray-100 dark:hover:bg-gray-700',
              'focus:bg-gray-100 focus:outline-none dark:focus:bg-gray-700',
              modelValue === team.id
                ? 'bg-gray-50 dark:bg-gray-700'
                : ''
            ]"
            @click="handleTeamSelect(team.id)"
          >
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="truncate text-sm font-medium">{{ team.name }}</span>
                <span
                  :class="[
                    'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                    getRoleBadge(team.current_user_role).color
                  ]"
                >
                  {{ getRoleBadge(team.current_user_role).label }}
                </span>
              </div>
              <div class="mt-0.5 flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400">
                <OIcon
                  collection="heroicons"
                  name="users"
                  class="size-3"
                  aria-hidden="true"
                />
                <span>{{ team.member_count }} {{ team.member_count === 1 ? t('web.teams.member') : t('web.teams.members') }}</span>
              </div>
            </div>

            <OIcon
              v-if="modelValue === team.id"
              collection="heroicons"
              name="check-20-solid"
              class="size-5 shrink-0 text-brand-500 dark:text-brand-400"
              aria-hidden="true"
            />
          </button>

          <div
            v-if="teams.length === 0"
            class="px-4 py-6 text-center text-sm text-gray-500 dark:text-gray-400"
          >
            {{ t('web.teams.no_teams') }}
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>
