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
  it('returns "Free" for free plan', () => {
    expect(getPlanLabel('free')).toBe('Free');
  });

  it('returns "Single Team" for single_team', () => {
    expect(getPlanLabel('single_team')).toBe('Single Team');
  });

  it('returns "Multi Team" for multi_team', () => {
    expect(getPlanLabel('multi_team')).toBe('Multi Team');
  });

  it('returns "Identity Plus" for identity_plus', () => {
    expect(getPlanLabel('identity_plus')).toBe('Identity Plus');
  });

  it('returns "Team Plus" for team_plus', () => {
    expect(getPlanLabel('team_plus')).toBe('Team Plus');
  });

  it('falls back to Title Case for unknown plan types', () => {
    expect(getPlanLabel('custom_plan')).toBe('Custom Plan');
  });
});
