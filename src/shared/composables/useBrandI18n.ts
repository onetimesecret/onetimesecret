// src/shared/composables/useBrandI18n.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { useI18n } from 'vue-i18n';

/**
 * Thin wrapper around useI18n that provides a `bt()` function for
 * brand-aware translations. `bt()` automatically injects the
 * `product_name` param from the bootstrap store into every call,
 * so locale keys containing `{product_name}` resolve without
 * call-site boilerplate.
 *
 * Usage:
 *   const { t, bt } = useBrandI18n();
 *   bt('web.homepage.welcome_to_onetime_secret')
 *   // → "Welcome to Onetime Secret" (or whatever brand_product_name is set to)
 *
 *   // Call-site params can override product_name if needed:
 *   bt('some.key', { product_name: 'Custom Name' })
 */
export function useBrandI18n() {
  const { t, ...rest } = useI18n();
  const { brand_product_name } = storeToRefs(useBootstrapStore());

  function bt(key: string, params?: Record<string, unknown>): string {
    return t(key, { product_name: brand_product_name.value, ...params });
  }

  return { t, bt, ...rest };
}
