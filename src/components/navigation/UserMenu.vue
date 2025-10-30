<!-- src/components/navigation/UserMenu.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import FancyIcon from '@/components/ctas/FancyIcon.vue';
import { Customer } from '@/schemas/models';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{
  cust: Customer | null;
  email?: string;  // Used when awaiting MFA (no customer object yet)
  colonel?: boolean;
  showUpgrade?: boolean;
  awaitingMfa?: boolean;
}>();

const { t } = useI18n();

const isOpen = ref(false);
const menuRef = ref<HTMLElement | null>(null);

// Get email from either customer object or direct prop (when awaiting MFA)
const userEmail = computed(() => props.cust?.email || props.email || '');

// Truncate email for display
const truncatedEmail = computed(() => {
  const email = userEmail.value;
  if (!email) return 'User';
  if (email.length <= 20) return email;
  const [local, domain] = email.split('@');
  return `${local.slice(0, 8)}...@${domain}`;
});

// Get user initials for avatar
const userInitials = computed(() => {
  const email = userEmail.value;
  if (!email) return '?';
  return email.charAt(0).toUpperCase();
});

// Toggle dropdown
const toggleMenu = () => {
  isOpen.value = !isOpen.value;
};

// Close dropdown
const closeMenu = () => {
  isOpen.value = false;
};

// Handle click outside
const handleClickOutside = (event: MouseEvent) => {
  if (menuRef.value && !menuRef.value.contains(event.target as Node)) {
    closeMenu();
  }
};

// Lifecycle hooks
onMounted(() => {
  document.addEventListener('click', handleClickOutside);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
});
</script>

<template>
  <div
    ref="menuRef"
    class="relative">
    <!-- Trigger Button -->
    <button
      @click="toggleMenu"
      class="flex items-center gap-2 rounded-md px-2 py-1.5
        text-sm text-gray-600 transition-colors duration-200
        hover:bg-gray-100 hover:text-gray-800
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-white
        dark:focus:ring-offset-gray-900"
      :aria-expanded="isOpen"
      aria-haspopup="true"
      :aria-label="t('web.COMMON.user_menu')">
      <!-- Avatar Circle with MFA indicator -->
      <div class="relative">
        <div
          :class="[
            'flex size-8 items-center justify-center rounded-full',
            'text-sm font-semibold text-white transition-colors',
            awaitingMfa
              ? 'bg-amber-500 dark:bg-amber-600'
              : 'bg-brand-500 dark:bg-brand-600'
          ]">
          {{ userInitials }}
        </div>
        <!-- MFA Pending Badge -->
        <div
          v-if="awaitingMfa"
          class="absolute -right-0.5 -top-0.5 size-2.5 rounded-full
            bg-amber-400 ring-2 ring-white dark:bg-amber-300 dark:ring-gray-900"
          :title="t('web.auth.mfa_required')"
          aria-label="MFA verification required">
        </div>
      </div>

      <!-- Email & Chevron -->
      <div class="hidden items-center gap-1 sm:flex">
        <span class="max-w-[150px] truncate">{{ truncatedEmail }}</span>
        <OIcon
          collection="heroicons"
          :name="isOpen ? 'chevron-up-solid' : 'chevron-down-solid'"
          class="size-4 transition-transform"
          aria-hidden="true" />
      </div>

      <!-- Mobile: Just show chevron -->
      <OIcon
        collection="heroicons"
        :name="isOpen ? 'chevron-up-solid' : 'chevron-down-solid'"
        class="size-4 transition-transform sm:hidden"
        aria-hidden="true" />
    </button>

    <!-- Dropdown Menu -->
    <Transition
      enter-active-class="transition duration-100 ease-out"
      enter-from-class="transform scale-95 opacity-0"
      enter-to-class="transform scale-100 opacity-100"
      leave-active-class="transition duration-75 ease-in"
      leave-from-class="transform scale-100 opacity-100"
      leave-to-class="transform scale-95 opacity-0">
      <div
        v-if="isOpen"
        class="absolute right-0 z-50 mt-2 w-64 origin-top-right
          rounded-lg bg-white shadow-lg ring-1 ring-black ring-opacity-5
          focus:outline-none dark:bg-gray-800 dark:ring-gray-700"
        role="menu"
        :aria-label="t('web.COMMON.user_menu')">
        <!-- User Info Header -->
        <div
          class="border-b border-gray-200 px-4 py-3
            dark:border-gray-700">
          <p
            class="text-sm font-medium text-gray-900 dark:text-white"
            :title="cust?.email">
            {{ cust?.email }}
          </p>
          <p
            v-if="cust?.objid"
            class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
            {{ cust?.extid }}
          </p>
          <!-- MFA Required Notice -->
          <div
            v-if="awaitingMfa"
            class="mt-2 flex items-center gap-2 rounded-md
              bg-amber-50 px-2 py-1.5 dark:bg-amber-900/20">
            <OIcon
              collection="heroicons"
              name="shield-exclamation-solid"
              class="size-4 text-amber-600 dark:text-amber-400"
              aria-hidden="true" />
            <span class="text-xs font-medium text-amber-700 dark:text-amber-300">
              {{ t('web.auth.mfa_verification_required') }}
            </span>
          </div>
        </div>

        <!-- Menu Items -->
        <nav class="py-1" role="navigation">
          <!-- Complete MFA (when awaiting) -->
          <router-link
            v-if="awaitingMfa"
            to="/mfa-verify"
            class="group flex items-center gap-3 px-4 py-2
              text-sm font-semibold text-amber-600 transition-colors
              hover:bg-amber-50 dark:text-amber-400
              dark:hover:bg-amber-900/20"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-5 text-amber-500 transition-colors
                group-hover:text-amber-600 dark:text-amber-400
                dark:group-hover:text-amber-300"
              aria-hidden="true" />
            {{ t('web.auth.complete_mfa_verification') }}
          </router-link>

          <!-- Divider after MFA prompt -->
          <div
            v-if="awaitingMfa"
            class="my-1 border-t border-gray-200 dark:border-gray-700"></div>

          <!-- Regular menu items (hidden when awaiting MFA) -->
          <template v-if="!awaitingMfa">
          <!-- Account Settings -->
          <router-link
            to="/account"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="cog-6-tooth-solid"
              class="size-5 text-gray-400 transition-colors
                group-hover:text-gray-600 dark:text-gray-500
                dark:group-hover:text-gray-300"
              aria-hidden="true" />
            {{ t('web.account.settings') }}
          </router-link>

          <!-- Security -->
          <router-link
            to="/account/settings/security"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-5 text-gray-400 transition-colors
                group-hover:text-gray-600 dark:text-gray-500
                dark:group-hover:text-gray-300"
              aria-hidden="true" />
            {{ t('web.COMMON.security') }}
          </router-link>

          <!-- Active Sessions -->
          <router-link
            to="/account/settings/security/sessions"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="computer-desktop-solid"
              class="size-5 text-gray-400 transition-colors
                group-hover:text-gray-600 dark:text-gray-500
                dark:group-hover:text-gray-300"
              aria-hidden="true" />
            {{ t('web.auth.sessions.title') }}
          </router-link>

          <!-- Data Region -->
          <router-link
            to="/account/region"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="globe-alt-solid"
              class="size-5 text-gray-400 transition-colors
                group-hover:text-gray-600 dark:text-gray-500
                dark:group-hover:text-gray-300"
              aria-hidden="true" />
            {{ t('web.account.region') }}
          </router-link>

          <!-- Divider -->
          <div class="my-1 border-t border-gray-200 dark:border-gray-700"></div>

          <!-- Upgrade \(conditional\) -->
          <router-link
            v-if="showUpgrade"
            to="/pricing"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-brand-600 transition-colors
              hover:bg-brand-50 dark:text-brand-400
              dark:hover:bg-brand-900/20"
            @click="closeMenu"
            role="menuitem">
            <FancyIcon />
            {{ t('web.LABELS.pricing') }}
          </router-link>

          <!-- Colonel (conditional) -->
          <router-link
            v-if="colonel"
            to="/colonel"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="mdi"
              name="star"
              class="size-5 text-brand-400 transition-colors
                group-hover:text-brand-500 dark:text-brand-400
                dark:group-hover:text-brand-300"
              aria-hidden="true" />
            {{ t('web.colonel.dashboard') }}
          </router-link>

          <!-- Divider -->
          <div
            v-if="showUpgrade || colonel"
            class="my-1 border-t border-gray-200 dark:border-gray-700"></div>
          </template>

          <!-- Logout (always show) -->
          <router-link
            to="/logout"
            class="group flex items-center gap-3 px-4 py-2
              text-sm text-red-600 transition-colors
              hover:bg-red-50 dark:text-red-400
              dark:hover:bg-red-900/20"
            @click="closeMenu"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="arrow-right-on-rectangle-solid"
              class="size-5 text-red-500 transition-colors
                group-hover:text-red-600 dark:text-red-400
                dark:group-hover:text-red-300"
              aria-hidden="true" />
            {{ t('web.COMMON.header_logout') }}
          </router-link>
        </nav>
      </div>
    </Transition>
  </div>
</template>
