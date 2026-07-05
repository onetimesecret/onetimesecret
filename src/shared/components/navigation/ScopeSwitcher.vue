<!-- src/shared/components/navigation/ScopeSwitcher.vue -->

<!--
  Scope Switcher (featurized engine)

  A single, reusable HeadlessUI Menu dropdown for switching between "scopes" —
  organizations, domains, or anything with the same shape. It owns:

    - the trigger button shell (styling, lock/disabled, aria, chevron)
    - the dropdown panel, header, row layout, checkmark/hover-gear, divider
    - THE INTERACTION that was historically buggy in the copy-pasted switchers:
      every navigating action dismisses the menu, and the gear icon's
      stopPropagation()-then-close() dance lives here exactly once. Fix it here
      and neither concrete switcher can regress.

  Concrete switchers (OrganizationScopeSwitcher, DomainContextSwitcher) are thin
  adapters: they map their objects into ScopeSwitcherItem[] and provide the
  variable visuals via slots. The engine never learns what an org or a domain is.

  Interaction contract:
    - `select`        emitted AFTER the engine has closed the menu.
    - `open-settings` emitted AFTER the engine has stopPropagation'd + closed.
  Adapters therefore only navigate; they never touch the menu's open state.
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue';

import type { ScopeSwitcherItem } from './scopeSwitcher';

interface Props {
  /** Rows to display. */
  items: ScopeSwitcherItem[];
  /** Uppercase panel header label. */
  header: string;
  /** When true the trigger shows the current scope but the dropdown is disabled. */
  locked?: boolean;
  /**
   * Gates the divider + footer region. Adapters pass whatever "can manage this
   * scope" means for them (owner/admin, entitlement, …); org always passes true
   * because its "Manage" link is unconditional.
   */
  canManage?: boolean;
  /** aria-label for the trigger button. */
  triggerAriaLabel: string;
  /** Trigger button title when unlocked (usually the current scope name). */
  triggerTitle?: string;
  /** Trigger button title when locked. */
  lockedTitle: string;
  /** aria-label for each row's settings (gear) button. */
  settingsLabel: string;
  /** Base test id: `${testid}` (root), `${testid}-trigger`, `${testid}-dropdown`. */
  testid: string;
  /** Row test id prefix: `${itemTestid}-${item.id}`. */
  itemTestid: string;
}

const props = withDefaults(defineProps<Props>(), {
  locked: false,
  canManage: false,
  triggerTitle: undefined,
});

const emit = defineEmits<{
  (e: 'select', id: string): void;
  (e: 'open-settings', id: string): void;
}>();

/**
 * Row click. Selecting a MenuItem already auto-closes the menu, so `close()`
 * here is a uniform belt-and-suspenders — it makes "every navigating action
 * closes the dropdown" a single invariant rather than a per-row judgement call.
 */
const onSelect = (item: ScopeSwitcherItem, close: () => void): void => {
  if (item.disabled) return;
  close();
  emit('select', item.id);
};

/**
 * Gear click. stopPropagation() keeps the row from also selecting, but it
 * suppresses HeadlessUI's built-in MenuItem auto-close — so we MUST close()
 * explicitly here. This is the exact bug that had to be fixed twice before;
 * now it lives in one place.
 */
const onSettings = (item: ScopeSwitcherItem, event: MouseEvent, close: () => void): void => {
  event.stopPropagation();
  close();
  emit('open-settings', item.id);
};
</script>

<template>
  <Menu
    as="div"
    class="relative inline-flex"
    :data-testid="testid"
    v-slot="{ open, close }">
    <!-- Trigger Button -->
    <MenuButton
      class="group inline-flex h-10 items-center gap-2 rounded-lg bg-gray-100 px-3 text-sm font-medium text-gray-700 transition-colors duration-150 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none dark:bg-gray-800 dark:text-gray-300 dark:focus:ring-offset-gray-900"
      :class="[
        props.locked
          ? 'cursor-default opacity-75'
          : 'hover:bg-gray-200 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-white',
      ]"
      :disabled="props.locked"
      :title="props.locked ? lockedTitle : triggerTitle"
      :aria-label="triggerAriaLabel"
      :aria-disabled="props.locked ? 'true' : undefined"
      :data-testid="`${testid}-trigger`">
      <!-- Leading visual + current-scope label (adapter-provided) -->
      <slot name="trigger"></slot>

      <!-- Chevron or Lock icon -->
      <OIcon
        v-if="props.locked"
        collection="heroicons"
        name="lock-closed"
        aria-label=""
        class="size-4 text-gray-400"
        aria-hidden="true" />
      <OIcon
        v-else
        collection="heroicons"
        :name="open ? 'chevron-up-solid' : 'chevron-down-solid'"
        aria-label=""
        class="size-4 text-gray-400 transition-transform"
        aria-hidden="true" />
    </MenuButton>

    <!-- Dropdown Menu -->
    <transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95">
      <MenuItems
        class="absolute top-full left-0 z-50 mt-1 max-h-60 w-max max-w-xs min-w-[220px] overflow-auto rounded-lg bg-white py-1 text-sm shadow-lg ring-1 ring-black/5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700"
        :data-testid="`${testid}-dropdown`">
        <!-- Header (label + optional adapter action, e.g. domain [+]) -->
        <div class="flex items-center justify-between px-3 py-2">
          <span
            class="font-brand text-xs font-semibold tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ header }}
          </span>
          <slot name="header-action" :close="close"></slot>
        </div>

        <!-- Scope Options -->
        <MenuItem
          v-for="item in items"
          :key="item.id"
          v-slot="{ active }"
          :disabled="item.disabled"
          @click="onSelect(item, close)">
          <button
            type="button"
            :data-testid="`${itemTestid}-${item.id}`"
            class="group/row relative w-full py-2 pr-9 pl-3 text-left transition-colors duration-150 select-none"
            :class="[
              item.disabled
                ? 'cursor-not-allowed text-gray-400 opacity-60 dark:text-gray-600'
                : 'cursor-pointer text-gray-700 dark:text-gray-200',
              !item.disabled && active ? 'bg-gray-100 dark:bg-gray-700' : '',
              item.isCurrent && !item.disabled ? 'bg-brand-50 dark:bg-brand-900/20' : '',
            ]"
            :title="item.disabled ? item.disabledReason : undefined"
            :aria-disabled="item.disabled ? 'true' : undefined">
            <span class="flex items-center gap-2">
              <!-- Leading visual (icon / avatar) -->
              <slot name="item-visual" :item="item"></slot>

              <!-- Scope Name -->
              <span
                class="block truncate"
                :class="{ 'font-semibold': item.isCurrent && !item.disabled }">
                {{ item.label }}
              </span>

              <!-- Trailing badge (e.g. paid-plan pill) -->
              <slot name="item-badge" :item="item"></slot>
            </span>

            <!-- Right action area: checkmark (active) / gear icon (on hover) -->
            <span class="absolute inset-y-0 right-0 flex items-center pr-3">
              <!-- Checkmark: visible for the active scope. Hidden on row hover
                   only when a gear will take its place. -->
              <OIcon
                v-if="item.isCurrent"
                collection="heroicons"
                name="check-20-solid"
                class="size-5 text-brand-600 dark:text-brand-400"
                :class="{ 'group-hover/row:hidden': item.hasSettings }"
                aria-hidden="true" />

              <!-- Gear icon: visible on row hover when the scope has settings -->
              <button
                v-if="item.hasSettings"
                type="button"
                class="hidden rounded p-0.5 text-gray-400 transition-colors group-hover/row:block hover:bg-gray-200 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-600 dark:hover:text-gray-300"
                :aria-label="settingsLabel"
                @click="onSettings(item, $event, close)">
                <OIcon
                  collection="heroicons"
                  name="cog"
                  class="size-4"
                  aria-hidden="true" />
              </button>
            </span>
          </button>
        </MenuItem>

        <!-- Divider + footer call to action (adapter-provided, gated by canManage) -->
        <template v-if="canManage">
          <div
            class="my-1 border-t border-gray-200 dark:border-gray-700"
            role="separator"
            aria-hidden="true"></div>
          <slot name="footer" :close="close"></slot>
        </template>
      </MenuItems>
    </transition>
  </Menu>
</template>
