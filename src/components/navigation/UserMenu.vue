<!-- src/components/navigation/UserMenu.vue -->

<!--
  "Complete MFA Verification" is shown in the UserMenu when:

  Condition: awaitingMfa prop is true

  This happens during the partial authentication state where:

  1. User has successfully completed the first authentication factor (password or magic link)
  2. But still needs to complete the second factor (MFA/TOTP code)
  3. Session has awaiting_mfa = true in the backend state

  Visual indicators when awaitingMfa is true:
  - Avatar circle background changes to amber/yellow (instead of brand blue)
  - Small amber pulse badge appears on top-right of avatar
  - Menu shows prominent "Complete MFA Verification" link in amber text at the top
  - Regular menu items are hidden (only MFA verification link shown)
  - Links to /mfa-verify route

  This state occurs in advanced authentication mode when:
  - User logs in with password but has MFA enabled
  - User clicks magic link but has MFA enabled
  - Backend sets session['awaiting_mfa'] = true
  - Frontend receives awaiting_mfa: true via /window endpoint
-->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import FancyIcon from '@/components/ctas/FancyIcon.vue';
import { Customer } from '@/schemas/models';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuth } from '@/composables/useAuth';
import { useTeamStore } from '@/stores/teamStore';
import { WindowService } from '@/services/window.service';

const props = defineProps<{
  cust: Customer | null;
  email?: string;  // Used when awaiting MFA (no customer object yet)
  colonel?: boolean;
  showUpgrade?: boolean;
  awaitingMfa?: boolean;
}>();

const { t } = useI18n();
const { logout } = useAuth();
const teamStore = useTeamStore();

const billingEnabled = computed(() => {
  try {
    return WindowService.get('billing_enabled') || false;
  } catch {
    return false;
  }
});

const isOpen = ref(false);
const menuRef = ref<HTMLElement | null>(null);

// Menu item type
interface MenuItem {
  id: string;
  to?: string;
  label: string;
  icon: {
    collection: string;
    name: string;
  };
  variant?: 'default' | 'caution' | 'danger' | 'cta';
  condition?: () => boolean;
  onClick?: () => void | Promise<void>;
}

// Define menu items
const menuItems = computed<MenuItem[]>(() => [
  // MFA Verification (when awaiting)
  {
    id: 'mfa-verify',
    to: '/mfa-verify',
    label: t('web.auth.complete_mfa_verification'),
    icon: { collection: 'heroicons', name: 'shield-check-solid' },
    variant: 'caution' as const,
    condition: () => props.awaitingMfa,
  },
  // Dashboard
  {
    id: 'dashboard',
    to: '/dashboard',
    label: t('web.TITLES.dashboard'),
    icon: { collection: 'heroicons', name: 'shield-check-solid' },
    condition: () => !props.awaitingMfa,
  },
  // Account Settings
  {
    id: 'account',
    to: '/account',
    label: t('web.account.settings'),
    icon: { collection: 'heroicons', name: 'cog-6-tooth-solid' },
    condition: () => !props.awaitingMfa,
  },
  // Billing (conditional - only show if billing enabled)
  {
    id: 'billing',
    to: '/billing',
    label: t('web.navigation.billing'),
    icon: { collection: 'heroicons', name: 'credit-card' },
    condition: () => !props.awaitingMfa && billingEnabled.value,
  },
  // Teams (conditional - only show if user has teams)
  {
    id: 'teams',
    to: '/teams',
    label: t('web.teams.menu.teams'),
    icon: { collection: 'heroicons', name: 'user-group-solid' },
    condition: () => !props.awaitingMfa && teamStore.hasTeams,
  },
  // Upgrade (conditional)
  {
    id: 'upgrade',
    to: '/pricing',
    label: t('upgrade-for-teams'),
    icon: { collection: 'tabler', name: 'square-letter-s-solid' },
    variant: 'cta' as const,
    condition: () => !props.awaitingMfa && props.showUpgrade,
  },
  // Colonel (conditional)
  {
    id: 'colonel',
    to: '/colonel',
    label: t('web.colonel.dashboard'),
    icon: { collection: 'mdi', name: 'star' },
    condition: () => !props.awaitingMfa && props.colonel,
  },
  // Logout (always show)
  {
    id: 'logout',
    label: t('web.COMMON.header_logout'),
    icon: { collection: 'heroicons', name: 'arrow-right-on-rectangle-solid' },
    variant: 'danger' as const,
    onClick: handleLogout,
  },
]);

// Visible menu items based on conditions
const visibleMenuItems = computed(() =>
  menuItems.value.filter(item => item.condition?.() ?? true)
);

// Check if we should show a divider before a menu item
const shouldShowDividerBefore = (item: MenuItem, index: number): boolean => {
  if (index === 0) return false;

  // Show divider after MFA verification
  if (visibleMenuItems.value[index - 1]?.id === 'mfa-verify') return true;

  // Show divider before upgrade/colonel section
  if (item.id === 'upgrade' || item.id === 'colonel') return true;

  // Show divider before logout
  if (item.id === 'logout') return true;

  return false;
};

// Get CSS classes for menu item based on variant
const getMenuItemClasses = (variant?: 'default' | 'caution' | 'danger' | 'cta'): string => {
  const baseClasses = 'group flex items-center gap-3 px-4 py-2 text-sm transition-colors';

  switch (variant) {
    case 'caution':
      return `${baseClasses} font-semibold text-amber-600 hover:bg-amber-50 dark:text-amber-400 dark:hover:bg-amber-900/20`;
    case 'danger':
      return `${baseClasses} text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/20`;
    case 'cta':
      return `${baseClasses} text-brand-600 hover:bg-brand-50 dark:text-brand-400 dark:hover:bg-brand-900/20`;
    default:
      return `${baseClasses} text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700`;
  }
};

// Get icon classes based on variant and item id
const getIconClasses = (variant?: 'default' | 'caution' | 'danger' | 'cta', itemId?: string): string => {
  const baseClasses = 'size-5 transition-colors';

  // Special case for colonel icon
  if (itemId === 'colonel') {
    return `${baseClasses} text-brand-400 group-hover:text-brand-500 dark:text-brand-400 dark:group-hover:text-brand-300`;
  }

  switch (variant) {
    case 'caution':
      return `${baseClasses} text-amber-500 group-hover:text-amber-600 dark:text-amber-400 dark:group-hover:text-amber-300`;
    case 'danger':
      return `${baseClasses} text-red-500 group-hover:text-red-600 dark:text-red-400 dark:group-hover:text-red-300`;
    case 'cta':
      return `${baseClasses} text-brand-500 group-hover:text-brand-600 dark:text-brand-400 dark:group-hover:text-brand-300`;
    default:
      return `${baseClasses} text-gray-400 group-hover:text-gray-600 dark:text-gray-500 dark:group-hover:text-gray-300`;
  }
};

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

// Handle logout
const handleLogout = async () => {
  closeMenu();
  await logout();
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
            v-if="!awaitingMfa && cust?.objid"
            class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
            {{ cust?.extid }}
          </p>
          <!-- MFA Required Notice -->
          <div
            v-if="awaitingMfa"
            class="mt-2 flex items-center gap-2 rounded-md px-2 py-1.5">
            <span class="text-sm font-medium ">
              {{ t('web.auth.mfa_verification_required') }}
            </span>
          </div>
        </div>

        <!-- Menu Items -->
        <nav class="py-1" role="navigation">
          <template
            v-for="(item, index) in visibleMenuItems"
            :key="item.id">
            <!-- Divider -->
            <div
              v-if="shouldShowDividerBefore(item, index)"
              class="my-1 border-t border-gray-200 dark:border-gray-700"></div>

            <!-- Router Link Item -->
            <router-link
              v-if="item.to"
              :to="item.to"
              :class="getMenuItemClasses(item.variant)"
              @click="closeMenu"
              role="menuitem">
              <!-- Special case for upgrade using FancyIcon -->
              <FancyIcon v-if="item.id === 'upgrade'" />
              <OIcon
                v-else
                :collection="item.icon.collection"
                :name="item.icon.name"
                :class="getIconClasses(item.variant, item.id)"
                aria-hidden="true" />
              {{ item.label }}
            </router-link>

            <!-- Button Item (for logout) -->
            <button
              v-else-if="item.onClick"
              :class="[getMenuItemClasses(item.variant), 'w-full']"
              @click="item.onClick"
              role="menuitem">
              <OIcon
                :collection="item.icon.collection"
                :name="item.icon.name"
                :class="getIconClasses(item.variant, item.id)"
                aria-hidden="true" />
              {{ item.label }}
            </button>
          </template>
        </nav>
      </div>
    </Transition>
  </div>
</template>
