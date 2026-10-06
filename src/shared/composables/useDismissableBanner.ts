// src/shared/composables/useDismissableBanner.ts

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
import { useHash } from '@/shared/composables/useHash';
import { ref, computed, watch } from 'vue';

interface BannerState {
  dismissed: boolean;
  timestamp: string | null;
}

interface BannerIdOptions {
  prefix: string;
  content: string | null;
}

/**
 * FNV-1a (32-bit) over the UTF-16 code units of `input`, as 8 hex characters.
 *
 * Not cryptographic and not meant to be: a banner ID only has to differ
 * between broadcasts with different text. Used when Web Crypto is
 * unavailable, which is every non-secure context (`crypto.subtle` is
 * undefined on a plain-HTTP self-hosted install).
 */
export function fnv1a32Hex(input: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    // 32-bit FNV prime multiply, kept in uint32 via Math.imul.
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
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

  // Use first 8 characters of the hash for the banner ID. When Web Crypto is
  // unavailable (non-secure context) fall back to a content hash rather than a
  // constant: a shared constant ID made dismissing one global broadcast hide
  // every future broadcast on HTTP installs (expirationDays 0 = permanent).
  const shortHash = hashHex ? hashHex.substring(0, 8) : fnv1a32Hex(content);

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
