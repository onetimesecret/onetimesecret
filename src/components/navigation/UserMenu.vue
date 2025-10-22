<!-- src/components/navigation/UserMenu.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { Customer } from '@/schemas/models';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useRouter } from 'vue-router';

const props = defineProps<{
  cust: Customer;
  colonel?: boolean;
  showUpgrade?: boolean;
}>();

const router = useRouter();
const isOpen = ref(false);
const menuRef = ref<HTMLElement | null>(null);

// Truncate email for display
const truncatedEmail = computed(() => {
  const email = props.cust.email;
  if (email.length <= 20) return email;
  const [local, domain] = email.split('@');
  return `${local.slice(0, 8)}...@${domain}`;
});

// Get user initials for avatar
const userInitials = computed(() => {
  const email = props.cust.email;
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

// Navigate to route
const navigateTo = (path: string) => {
  closeMenu();
  router.push(path);
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
      :aria-label="$t('web.COMMON.user_menu')">
      <!-- Avatar Circle -->
      <div
        class="flex size-8 items-center justify-center rounded-full
          bg-brand-500 text-sm font-semibold text-white
          dark:bg-brand-600">
        {{ userInitials }}
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
        :aria-label="$t('web.COMMON.user_menu')">
        <!-- User Info Header -->
        <div
          class="border-b border-gray-200 px-4 py-3
            dark:border-gray-700">
          <p
            class="text-sm font-medium text-gray-900 dark:text-white"
            :title="cust.email">
            {{ cust.email }}
          </p>
          <p
            v-if="cust.custid"
            class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
            {{ $t('web.account.customer-id') }}: {{ cust.custid }}
          </p>
        </div>

        <!-- Menu Items -->
        <div class="py-1">
          <!-- Account Settings -->
          <button
            @click="navigateTo('/account/settings')"
            class="flex w-full items-center gap-3 px-4 py-2
              text-left text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="cog-6-tooth-solid"
              class="size-5 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            {{ $t('web.account.settings') }}
          </button>

          <!-- Security -->
          <button
            @click="navigateTo('/account/settings/mfa')"
            class="flex w-full items-center gap-3 px-4 py-2
              text-left text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-5 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            {{ $t('web.COMMON.security') }}
          </button>

          <!-- Active Sessions -->
          <button
            @click="navigateTo('/account/settings/sessions')"
            class="flex w-full items-center gap-3 px-4 py-2
              text-left text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="computer-desktop-solid"
              class="size-5 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            {{ $t('web.auth.sessions.title') }}
          </button>

          <!-- Divider -->
          <div class="my-1 border-t border-gray-200 dark:border-gray-700"></div>

          <!-- Upgrade (conditional) -->
          <button
            v-if="showUpgrade"
            @click="navigateTo('/pricing')"
            class="flex w-full items-center gap-3 px-4 py-2
              text-left text-sm text-brand-600 transition-colors
              hover:bg-brand-50 dark:text-brand-400
              dark:hover:bg-brand-900/20"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="bolt-solid"
              class="size-5 text-brand-500 dark:text-brand-400"
              aria-hidden="true" />
            {{ $t('web.LABELS.pricing') }}
          </button>

          <!-- Colonel (conditional) -->
          <button
            v-if="colonel"
            @click="navigateTo('/colonel')"
            class="flex w-full items-center gap-3 px-4 py-2
              text-left text-sm text-gray-700 transition-colors
              hover:bg-gray-100 dark:text-gray-300
              dark:hover:bg-gray-700"
            role="menuitem">
            <OIcon
              collection="mdi"
              name="star"
              class="size-5 text-brand-400"
              aria-hidden="true" />
            {{ $t('web.colonel.dashboard') }}
          </button>

          <!-- Divider -->
          <div
            v-if="showUpgrade || colonel"
            class="my-1 border-t border-gray-200 dark:border-gray-700"></div>

          <!-- Logout -->
          <button
            @click="navigateTo('/logout')"
            class="flex w-full items-center gap-3 px-4 py-2
              text-left text-sm text-red-600 transition-colors
              hover:bg-red-50 dark:text-red-400
              dark:hover:bg-red-900/20"
            role="menuitem">
            <OIcon
              collection="heroicons"
              name="arrow-right-on-rectangle-solid"
              class="size-5 text-red-500 dark:text-red-400"
              aria-hidden="true" />
            {{ $t('web.COMMON.header_logout') }}
          </button>
        </div>
      </div>
    </Transition>
  </div>
</template>
