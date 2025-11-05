// src/composables/usePageTitle.ts

import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';

/**
 * Composable for managing page titles and meta tags dynamically.
 *
 * Features:
 * - Automatic title updates with app name suffix
 * - i18n support for translated titles
 * - Meta tag updates (og:title, twitter:title)
 * - TypeScript support for route meta
 *
 * @example
 * // In a component
 * const { setTitle } = usePageTitle();
 * setTitle('Custom Page');
 *
 * @example
 * // With i18n key
 * const { setTitle } = usePageTitle();
 * setTitle('DASHBOARD.TITLE'); // Will translate automatically
 */

const APP_NAME = 'Onetime Secret';
const TITLE_SEPARATOR = ' - ';

export function usePageTitle() {
  const { t, te } = useI18n();

  /**
   * Gets the branded app name from domain settings or defaults to APP_NAME
   */
  const getAppName = (): string => {
    const domainBranding = WindowService.get('domain_branding');
    return domainBranding?.display_domain || APP_NAME;
  };

  /**
   * Translates a title if it's an i18n key, otherwise returns the raw string
   * @param title - Either a plain string or an i18n key
   * @returns Translated or original title
   */
  const translateTitle = (title: string): string => {
    // Check if it's an i18n key (e.g., 'DASHBOARD.TITLE')
    if (te(title)) {
      return t(title);
    }
    return title;
  };

  /**
   * Formats the complete page title with app name suffix
   * @param pageTitle - The page-specific title
   * @returns Formatted title string
   */
  const formatTitle = (pageTitle: string): string => {
    const appName = getAppName();
    const translatedTitle = translateTitle(pageTitle);

    if (!translatedTitle || translatedTitle === appName) {
      return appName;
    }

    return `${translatedTitle}${TITLE_SEPARATOR}${appName}`;
  };

  /**
   * Updates the document title and related meta tags
   * @param title - The new title (can be plain string or i18n key)
   */
  const setTitle = (title: string | null | undefined) => {
    const finalTitle = title ? formatTitle(title) : getAppName();

    // Update document title
    document.title = finalTitle;

    // Update Open Graph meta tag
    const ogTitleMeta = document.querySelector('meta[property="og:title"]');
    if (ogTitleMeta) {
      ogTitleMeta.setAttribute('content', finalTitle);
    }

    // Update Twitter meta tag
    const twitterTitleMeta = document.querySelector('meta[name="twitter:title"]');
    if (twitterTitleMeta) {
      twitterTitleMeta.setAttribute('content', finalTitle);
    }
  };

  /**
   * Creates a computed title that automatically updates when dependencies change
   * Useful for reactive titles based on component state
   *
   * @param titleGetter - Function that returns the current title
   * @returns Computed title value
   *
   * @example
   * const secretId = ref('abc123');
   * const title = useComputedTitle(() => `Secret ${secretId.value}`);
   * watch(title, (newTitle) => setTitle(newTitle));
   */
  const useComputedTitle = (titleGetter: () => string) => {
    const title = computed(titleGetter);

    watch(title, (newTitle) => {
      setTitle(newTitle);
    }, { immediate: true });

    return title;
  };

  return {
    setTitle,
    useComputedTitle,
    formatTitle,
  };
}

/**
 * Type extension for route meta to include title property
 * Add this to your router type declarations
 */
export interface RouteMeta {
  title?: string;
  requiresAuth?: boolean;
  isAuthRoute?: boolean;
  layout?: string;
  layoutProps?: Record<string, unknown>;
}
