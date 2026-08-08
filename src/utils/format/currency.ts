// src/utils/format/currency.ts

/**
 * Locale-aware currency formatting (#4048).
 *
 * Components should use this wrapper instead of calling the base helper in
 * `@/types/billing` directly: it resolves the app's ACTIVE i18n locale so the
 * language switcher affects price formatting, instead of silently using the
 * browser locale (which differs between visitors).
 *
 * The wrapper lives here (not in `@/types/billing`) because importing the
 * `@/i18n` instance from the types module would drag the full i18n bootstrap
 * (vue-i18n + all merged locale files) into every consumer of the billing
 * types, and break the many vitest specs that partially mock `vue-i18n`.
 */
import { globalComposer } from '@/i18n';
import { formatCurrency as baseFormatCurrency } from '@/types/billing';

/**
 * Resolve the app's active i18n locale as a BCP-47 tag for Intl.* APIs.
 *
 * App locale codes use underscores (de_AT, fr_CA); Intl expects hyphens.
 * Returns undefined when no app locale is available, letting Intl fall back
 * to the browser locale.
 */
export function activeIntlLocale(): string | undefined {
  try {
    const locale = globalComposer.locale.value;
    return locale ? String(locale).replace(/_/g, '-') : undefined;
  } catch {
    // i18n not initialized (or mocked away in tests) — browser locale fallback.
    return undefined;
  }
}

/**
 * Format an amount in cents using the app's active locale.
 *
 * @param amount - Amount in cents
 * @param currency - ISO 4217 currency code; falsy values coerce to 'USD'
 */
export function formatCurrency(amount: number, currency?: string | null): string {
  return baseFormatCurrency(amount, currency, activeIntlLocale());
}
