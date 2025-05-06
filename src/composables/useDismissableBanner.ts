// useDismissableBanner.ts

/**
 * <script setup lang="ts">
 * import { useDismissableBanner } from '@/composables/useDismissableBanner'
 *
 * // Banner that never reappears once dismissed
 * const { isVisible: isAnnouncementVisible, dismiss: dismissAnnouncement } =
 *   useDismissableBanner('announcement')
 *
 * // Banner that reappears after 7 days
 * const { isVisible: isPromoVisible, dismiss: dismissPromo } =
 *   useDismissableBanner('promo', 7)
 *
 * // Banner with ID generated from content
 * const bannerContent = "Welcome to our site!"
 * const { isVisible, dismiss } = useDismissableBanner({
 *   prefix: 'welcome',
 *   content: bannerContent
 * }, 7)
 * </script>
 *
 * <template>
 *   <!-- Permanent dismissal banner -->
 *   <div v-if="isAnnouncementVisible">
 *     <p>Important announcement that you only need to see once!</p>
 *     <button @click="dismissAnnouncement">
 *       X
 *     </button>
 *   </div>
 *
 *   <!-- Time-limited dismissal banner -->
 *   <div v-if="isPromoVisible">
 *     <button @click="dismissPromo">Dismiss</button>
 *   </div>
 * </template>
 */
import { ref, computed, watch } from 'vue';
import { useHash } from '@/composables/useHash';

interface BannerState {
  dismissed: boolean;
  timestamp: string | null;
}

interface BannerIdOptions {
  prefix: string;
  content: string | null;
}

/**
 * Generates a unique banner ID based on content
 * @param options - Object containing prefix and content
 * @returns Generated banner ID
 */
export async function generateBannerId(options: BannerIdOptions): Promise<string> {
  const { prefix, content } = options;

  // If no content, use default
  if (!content) {
    return `${prefix}-default`;
  }

  // Use the useHash composable to generate a SHA-256 hash
  const { generateHash } = useHash();
  const hashHex = await generateHash(content);

  // Use first 8 characters of the hash for the banner ID
  const shortHash = hashHex ? hashHex.substring(0, 8) : 'fallback';

  return `${prefix}-${shortHash}`;
}

/**
 * Composable for managing dismissable banners with optional expiration
 * @param bannerIdOrOptions - String ID or options for generating ID from content
 * @param expirationDays - Optional number of days until the banner reappears (0 for never)
 * @returns Object with isVisible state and dismiss function
 */
export function useDismissableBanner(
  bannerIdOrOptions: string | BannerIdOptions,
  expirationDays: number = 0
) {
  // Determine the actual banner ID to use - for object options, use a placeholder
  // that will be updated when the async ID generation completes
  const bannerId = ref(
    typeof bannerIdOrOptions === 'string'
      ? bannerIdOrOptions
      : `${bannerIdOrOptions.prefix}-initial`
  );

  // If we received options, generate the ID asynchronously
  if (typeof bannerIdOrOptions !== 'string') {
    generateBannerId(bannerIdOrOptions).then((id) => {
      bannerId.value = id;
    });
  }

  // Initialize state from localStorage or with defaults
  const getStoredState = (): BannerState => {
    const stored = localStorage.getItem(`banner-${bannerId.value}`);
    if (stored) {
      try {
        const parsedState = JSON.parse(stored);
        // Basic validation to ensure it's at least an object with expected keys,
        // though a more robust validation (e.g., with Zod) could be used here.
        if (
          typeof parsedState === 'object' &&
          parsedState !== null &&
          'dismissed' in parsedState &&
          'timestamp' in parsedState
        ) {
          return parsedState as BannerState;
        }
        // If the structure is not what we expect, treat as invalid.
        console.warn(`Invalid banner state structure for ${bannerId.value}:`, parsedState);
        return { dismissed: false, timestamp: null };
      } catch (error) {
        // If JSON parsing fails, log the error and return default state.
        console.warn(
          `Failed to parse banner state for ${bannerId.value} from localStorage:`,
          error
        );
        return { dismissed: false, timestamp: null };
      }
    }
    return { dismissed: false, timestamp: null };
  };

  // Create reactive state
  const bannerState = ref<BannerState>(getStoredState());

  // Re-read storage when bannerId changes (when async generation completes)
  watch(bannerId, () => {
    bannerState.value = getStoredState();
  });

  // Computed property to determine if banner should be visible
  const isVisible = computed(() => {
    if (!bannerState.value.dismissed) return true;
    if (expirationDays === 0) return false; // Never show again if expiration is 0

    const dismissedTime = bannerState.value.timestamp
      ? new Date(bannerState.value.timestamp).getTime()
      : 0;
    const currentTime = new Date().getTime();
    const daysPassed = (currentTime - dismissedTime) / (1000 * 60 * 60 * 24);

    return daysPassed > expirationDays;
  });

  // Function to dismiss the banner
  const dismiss = () => {
    bannerState.value = {
      dismissed: true,
      timestamp: new Date().toISOString(),
    };
    localStorage.setItem(`banner-${bannerId.value}`, JSON.stringify(bannerState.value));
  };

  return {
    isVisible,
    dismiss,
    bannerId: computed(() => bannerId.value),
  };
}
