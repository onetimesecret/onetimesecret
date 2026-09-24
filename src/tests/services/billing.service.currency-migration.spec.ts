// src/tests/services/billing.service.currency-migration.spec.ts

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Use vi.hoisted to properly hoist mock functions before vi.mock
const { mockGet, mockPost } = vi.hoisted(() => ({
  mockGet: vi.fn(),
  mockPost: vi.fn(),
}));

vi.mock('@/api', () => ({
  createApi: () => ({
    get: mockGet,
    post: mockPost,
  }),
}));

// Import after mocking
import {
  BillingService,
  extractCurrencyConflict,
} from '@/services/billing.service';
import {
  immediateMigrationResponseSchema,
  migrateCurrencyResponseSchema,
} from '@/schemas/contracts/billing';

describe('Currency migration service methods', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockReset();
    mockPost.mockReset();
  });

  describe('BillingService.migrateCurrency', () => {
    it('calls correct endpoint with graceful mode', async () => {
      const mockResponse = {
        data: {
          success: true,
          migration: { mode: 'graceful', cancel_at: 1704067200 },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.migrateCurrency('org_abc', {
        new_price_id: 'price_cad_123',
        mode: 'graceful',
      });

      expect(mockPost).toHaveBeenCalledWith(
        '/billing/api/org/org_abc/migrate-currency',
        { new_price_id: 'price_cad_123', mode: 'graceful' }
      );
      expect(result.success).toBe(true);
      expect(result.migration.mode).toBe('graceful');
      if (result.migration.mode !== 'graceful') throw new Error('expected graceful mode');
      expect(result.migration.cancel_at).toBe(1704067200);
    });

    it('calls correct endpoint with immediate mode', async () => {
      // Live shape (currency_migration_service.rb): checkout_url/refund_* —
      // see the migrateCurrency() comment in billing.service.ts.
      const mockResponse = {
        data: {
          success: true,
          migration: {
            mode: 'immediate',
            checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_123',
            refund_amount: 1500,
            refund_formatted: 'EUR 15.00',
            refund_failed: false,
          },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.migrateCurrency('org_xyz', {
        new_price_id: 'price_eur_456',
        mode: 'immediate',
      });

      expect(mockPost).toHaveBeenCalledWith(
        '/billing/api/org/org_xyz/migrate-currency',
        { new_price_id: 'price_eur_456', mode: 'immediate' }
      );
      expect(result.success).toBe(true);
      expect(result.migration.mode).toBe('immediate');
      if (result.migration.mode !== 'immediate') throw new Error('expected immediate mode');
      expect(result.migration.checkout_url).toContain('stripe.com');
    });

    it('propagates API errors', async () => {
      mockPost.mockRejectedValueOnce(new Error('Subscription is past_due'));

      await expect(
        BillingService.migrateCurrency('org_test', {
          new_price_id: 'price_abc',
          mode: 'graceful',
        })
      ).rejects.toThrow('Subscription is past_due');
    });
  });

  describe('immediateMigrationResponseSchema refund_failed', () => {
    const baseResponse = {
      success: true as const,
      migration: {
        mode: 'immediate' as const,
        checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_123',
        refund_amount: 0,
        refund_formatted: '€0.00',
      },
    };

    it('preserves refund_failed: true through parsing (Zod must not strip it)', () => {
      const parsed = immediateMigrationResponseSchema.parse({
        ...baseResponse,
        migration: { ...baseResponse.migration, refund_failed: true },
      });
      expect(parsed.migration.refund_failed).toBe(true);
    });

    it('defaults refund_failed to false when absent (older backend tolerance)', () => {
      const parsed = immediateMigrationResponseSchema.parse(baseResponse);
      expect(parsed.migration.refund_failed).toBe(false);
    });

    it('preserves refund_failed through the migrate-currency union schema', () => {
      const parsed = migrateCurrencyResponseSchema.parse({
        ...baseResponse,
        migration: { ...baseResponse.migration, refund_failed: true },
      });
      expect(
        parsed.migration.mode === 'immediate' && parsed.migration.refund_failed
      ).toBe(true);
    });
  });

  describe('extractCurrencyConflict', () => {
    it('extracts conflict details from 409 response', () => {
      // Build an error-like object matching what axios produces at runtime.
      // The extractCurrencyConflict function checks 'response' in error,
      // then data.code === 'currency_conflict'. Shape verified against the
      // live billing controller (checkout 409 branch): { error, code,
      // details: { existing_currency, requested_currency, current_plan,
      // requested_plan, warnings } } — not a flat payload.
      const conflictData = {
        error: true,
        code: 'currency_conflict',
        message: 'A currency change is required.',
        details: {
          existing_currency: 'eur',
          requested_currency: 'cad',
          current_plan: {
            name: 'Identity Plus',
            price_formatted: '€9.00',
            current_period_end: 1704067200,
          },
          requested_plan: {
            name: 'Team Plus',
            price_formatted: 'CA$99.00',
            price_id: 'price_cad_456',
          },
          warnings: {
            has_credit_balance: false,
            credit_balance_amount: 0,
            has_pending_invoice_items: false,
            has_incompatible_coupons: false,
          },
        },
      };

      // Simulate axios-shaped error with response property
      const error = {
        response: {
          status: 409,
          data: conflictData,
        },
      };

      const result = extractCurrencyConflict(error);

      expect(result).not.toBeNull();
      expect(result?.details.existing_currency).toBe('eur');
      expect(result?.details.requested_currency).toBe('cad');
      expect(result?.details.requested_plan?.price_id).toBe('price_cad_456');
    });

    it('returns null for non-409 errors', () => {
      const error = {
        response: { status: 400, data: { message: 'Missing product' } },
      };
      expect(extractCurrencyConflict(error)).toBeNull();
    });

    it('returns null for 409 without currency_conflict code', () => {
      const error = {
        response: { status: 409, data: { code: 'generic_conflict', message: 'Something else' } },
      };
      expect(extractCurrencyConflict(error)).toBeNull();
    });

    it('returns null for non-object errors', () => {
      expect(extractCurrencyConflict('string error')).toBeNull();
      expect(extractCurrencyConflict(null)).toBeNull();
      expect(extractCurrencyConflict(undefined)).toBeNull();
      expect(extractCurrencyConflict(42)).toBeNull();
    });

    it('returns null for objects without response property', () => {
      expect(extractCurrencyConflict(new Error('plain error'))).toBeNull();
      expect(extractCurrencyConflict({ message: 'not axios' })).toBeNull();
    });
  });
});
