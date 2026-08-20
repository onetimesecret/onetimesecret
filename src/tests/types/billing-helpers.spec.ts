// src/tests/types/billing-helpers.spec.ts

/**
 * Unit tests for billing helper functions:
 * - formatCurrency: Intl-based currency formatting from cents
 * - getInvoiceStatusLabel: i18n-aware invoice status display
 * - getSubscriptionStatusLabel: i18n-aware subscription status display
 * - getPlanLabel: plan type display labels
 */

import { describe, it, expect, vi } from 'vitest';

// Mock vue-i18n before importing billing helpers
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

import {
  formatCurrency,
  getInvoiceStatusLabel,
  getSubscriptionStatusLabel,
  getPlanLabel,
} from '@/types/billing';
import type { ComposerTranslation } from 'vue-i18n';

// Stub translation function that returns the key
const mockT = ((key: string) => key) as unknown as ComposerTranslation;

describe('formatCurrency', () => {
  it('converts cents to dollars for USD', () => {
    expect(formatCurrency(2900, 'USD')).toContain('29');
  });

  it('formats zero correctly', () => {
    expect(formatCurrency(0, 'USD')).toContain('0');
  });

  it('handles large amounts', () => {
    expect(formatCurrency(99000, 'USD')).toContain('990');
  });

  it('handles single cent', () => {
    const result = formatCurrency(1, 'USD');
    expect(result).toContain('0.01');
  });

  it('defaults to USD when no currency specified', () => {
    const result = formatCurrency(5000);
    expect(result).toContain('50');
  });

  it('falls back to USD when currency is null instead of throwing', () => {
    // A plan can reach the UI with a null currency (no Stripe price currency
    // and no plan currency), which used to crash Intl.NumberFormat.
    expect(() => formatCurrency(5000, null)).not.toThrow();
    expect(formatCurrency(5000, null)).toContain('50');
  });

  it('falls back to USD when currency is an empty string', () => {
    expect(() => formatCurrency(5000, '')).not.toThrow();
    expect(formatCurrency(5000, '')).toContain('50');
  });

  it('formats EUR currency', () => {
    const result = formatCurrency(1999, 'EUR');
    expect(result).toContain('19.99');
  });

  it('formats GBP currency', () => {
    const result = formatCurrency(3500, 'GBP');
    expect(result).toContain('35');
  });

  it('handles negative amounts (refunds)', () => {
    const result = formatCurrency(-2900, 'USD');
    expect(result).toContain('29');
  });

  describe('locale parameter (#4048 defect 1)', () => {
    it('formats with the given locale', () => {
      // de uses "29,00 €", en-US uses "€29.00"
      expect(formatCurrency(2900, 'EUR', 'de')).toBe(
        new Intl.NumberFormat('de', { style: 'currency', currency: 'EUR' }).format(29)
      );
      expect(formatCurrency(2900, 'EUR', 'en-US')).toBe(
        new Intl.NumberFormat('en-US', { style: 'currency', currency: 'EUR' }).format(29)
      );
    });

    it('produces different output for de vs en-US with EUR', () => {
      expect(formatCurrency(123456, 'EUR', 'de')).not.toBe(formatCurrency(123456, 'EUR', 'en-US'));
    });

    it('normalizes underscore locales (de_AT, fr_CA) to BCP-47', () => {
      expect(formatCurrency(2900, 'EUR', 'de_AT')).toBe(
        new Intl.NumberFormat('de-AT', { style: 'currency', currency: 'EUR' }).format(29)
      );
      expect(formatCurrency(2900, 'CAD', 'fr_CA')).toBe(
        new Intl.NumberFormat('fr-CA', { style: 'currency', currency: 'CAD' }).format(29)
      );
    });

    it('falls back to browser locale when no locale given', () => {
      expect(formatCurrency(2900, 'USD')).toBe(
        new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(29)
      );
    });

    it('falls back to browser locale on an invalid locale tag', () => {
      expect(formatCurrency(2900, 'USD', '!!not-a-locale!!')).toBe(
        new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(29)
      );
    });
  });

  describe('defensive currency handling (#4048 defect 3)', () => {
    it('coerces null currency to USD instead of throwing', () => {
      expect(formatCurrency(2900, null)).toContain('29');
      expect(() => formatCurrency(2900, null)).not.toThrow();
    });

    it('coerces empty-string currency to USD', () => {
      expect(formatCurrency(2900, '')).toBe(
        new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(29)
      );
    });

    it('accepts lowercase currency codes', () => {
      expect(formatCurrency(2900, 'eur')).toBe(
        new Intl.NumberFormat(undefined, { style: 'currency', currency: 'EUR' }).format(29)
      );
    });

    it('degrades to plain rendering for a garbage currency code', () => {
      expect(formatCurrency(1999, 'NOTREAL')).toBe('19.99 NOTREAL');
    });

    it('degrades to plain rendering for garbage currency with a locale', () => {
      // Malformed (non 3-letter) code throws RangeError for every locale
      expect(formatCurrency(1999, 'X9', 'de')).toBe('19.99 X9');
    });
  });
});

describe('getInvoiceStatusLabel', () => {
  it('returns i18n key for paid status', () => {
    expect(getInvoiceStatusLabel('paid', mockT))
      .toBe('web.billing.invoices.paid');
  });

  it('returns i18n key for pending status', () => {
    expect(getInvoiceStatusLabel('pending', mockT))
      .toBe('web.billing.invoices.pending');
  });

  it('returns i18n key for failed status', () => {
    expect(getInvoiceStatusLabel('failed', mockT))
      .toBe('web.billing.invoices.failed');
  });

  it('returns i18n key for draft status', () => {
    expect(getInvoiceStatusLabel('draft', mockT))
      .toBe('web.billing.invoices.draft');
  });

  it('returns i18n key for open status', () => {
    expect(getInvoiceStatusLabel('open', mockT))
      .toBe('web.billing.invoices.open');
  });

  it('returns i18n key for uncollectible status', () => {
    expect(getInvoiceStatusLabel('uncollectible', mockT))
      .toBe('web.billing.invoices.uncollectible');
  });

  it('returns i18n key for void status', () => {
    expect(getInvoiceStatusLabel('void', mockT))
      .toBe('web.billing.invoices.void');
  });
});

describe('getSubscriptionStatusLabel', () => {
  it('returns i18n key for active status', () => {
    expect(getSubscriptionStatusLabel('active', mockT))
      .toBe('web.billing.subscription.active');
  });

  it('returns i18n key for inactive status', () => {
    expect(getSubscriptionStatusLabel('inactive', mockT))
      .toBe('web.billing.subscription.inactive');
  });

  it('returns i18n key for past_due status', () => {
    expect(getSubscriptionStatusLabel('past_due', mockT))
      .toBe('web.billing.subscription.past_due');
  });

  it('returns i18n key for canceled status', () => {
    expect(getSubscriptionStatusLabel('canceled', mockT))
      .toBe('web.billing.subscription.canceled');
  });
});

describe('getPlanLabel', () => {
  it('returns "Free" for free_v1 plan ID', () => {
    expect(getPlanLabel('free_v1')).toBe('Free');
  });

  it('returns "Identity Plus" for identity_plus_v1 plan ID', () => {
    expect(getPlanLabel('identity_plus_v1')).toBe('Identity Plus');
  });

  it('returns "Team Plus" for team_plus_v1 plan ID', () => {
    expect(getPlanLabel('team_plus_v1')).toBe('Team Plus');
  });

  it('returns "Identity Plus (Early Supporter)" for legacy identity plan', () => {
    expect(getPlanLabel('identity')).toBe('Identity Plus (Early Supporter)');
  });

  it('returns input unchanged for unmapped values', () => {
    expect(getPlanLabel('custom_plan')).toBe('custom_plan');
    expect(getPlanLabel('single_team')).toBe('single_team');
  });
});
