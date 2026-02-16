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
        new_price_id: 'price_usd_123',
        mode: 'graceful',
      });

      expect(mockPost).toHaveBeenCalledWith(
        '/billing/api/org/org_abc/migrate-currency',
        { new_price_id: 'price_usd_123', mode: 'graceful' }
      );
      expect(result.success).toBe(true);
      expect(result.migration.mode).toBe('graceful');
      expect(result.migration.cancel_at).toBe(1704067200);
    });

    it('calls correct endpoint with immediate mode', async () => {
      const mockResponse = {
        data: {
          success: true,
          migration: {
            mode: 'immediate',
            checkout_session_url: 'https://checkout.stripe.com/c/pay/cs_test_123',
            prorated_credit_amount: 1500,
            prorated_credit_formatted: 'EUR 15.00',
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
      expect(result.migration.checkout_session_url).toContain('stripe.com');
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

  describe('extractCurrencyConflict', () => {
    it('extracts conflict details from 409 response', () => {
      // Build an error-like object matching what axios produces at runtime.
      // The extractCurrencyConflict function checks 'response' in error,
      // then data.code === 'currency_conflict'.
      const conflictData = {
        code: 'currency_conflict',
        error: 'currency_conflict',
        message: 'A currency change is required.',
        current_currency: 'eur',
        requested_currency: 'usd',
        current_plan_name: 'Identity Plus',
        current_period_end: 1704067200,
        new_plan_name: 'Team Plus',
        new_plan_amount: 9900,
        new_plan_interval: 'month',
        new_price_id: 'price_usd_456',
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
      expect(result?.current_currency).toBe('eur');
      expect(result?.requested_currency).toBe('usd');
      expect(result?.new_price_id).toBe('price_usd_456');
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
