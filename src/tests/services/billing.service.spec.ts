// src/tests/services/billing.service.spec.ts

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
import { BillingService } from '@/services/billing.service';

describe('BillingService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockReset();
    mockPost.mockReset();
  });

  describe('getSubscriptionStatus', () => {
    it('calls correct endpoint with org extid', async () => {
      const mockResponse = {
        data: {
          has_active_subscription: true,
          current_plan: 'identity_plus_v1_monthly',
          current_price_id: 'price_123',
          subscription_item_id: 'si_123',
          subscription_status: 'active',
          current_period_end: 1704067200,
        },
      };
      mockGet.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.getSubscriptionStatus('org_abc123');

      expect(mockGet).toHaveBeenCalledWith('/billing/api/org/org_abc123/subscription');
      expect(result).toEqual(mockResponse.data);
    });

    it('returns inactive subscription status', async () => {
      const mockResponse = {
        data: {
          has_active_subscription: false,
          current_plan: null,
        },
      };
      mockGet.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.getSubscriptionStatus('org_xyz');

      expect(result.has_active_subscription).toBe(false);
      expect(result.current_plan).toBeNull();
    });
  });

  describe('previewPlanChange', () => {
    it('calls correct endpoint with price id', async () => {
      const mockResponse = {
        data: {
          amount_due: 5000,
          subtotal: 9900,
          credit_applied: 4900,
          next_billing_date: 1704067200,
          currency: 'usd',
          current_plan: {
            price_id: 'price_old',
            amount: 4900,
            interval: 'month',
          },
          new_plan: {
            price_id: 'price_new',
            amount: 9900,
            interval: 'month',
          },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.previewPlanChange('org_123', 'price_new');

      expect(mockPost).toHaveBeenCalledWith(
        '/billing/api/org/org_123/preview-plan-change',
        { new_price_id: 'price_new' }
      );
      expect(result).toEqual(mockResponse.data);
    });

    it('returns proration preview details', async () => {
      const mockResponse = {
        data: {
          amount_due: 7000,
          credit_applied: 2900,
          currency: 'usd',
          current_plan: { price_id: 'price_a', amount: 2900, interval: 'month' },
          new_plan: { price_id: 'price_b', amount: 9900, interval: 'month' },
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.previewPlanChange('org_test', 'price_b');

      expect(result.amount_due).toBe(7000);
      expect(result.credit_applied).toBe(2900);
      expect(result.new_plan.amount).toBe(9900);
    });
  });

  describe('changePlan', () => {
    it('calls correct endpoint with price id', async () => {
      const mockResponse = {
        data: {
          success: true,
          new_plan: 'team_plus_v1_monthly',
          status: 'active',
          current_period_end: 1704067200,
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.changePlan('org_abc', 'price_xyz');

      expect(mockPost).toHaveBeenCalledWith(
        '/billing/api/org/org_abc/change-plan',
        { new_price_id: 'price_xyz' }
      );
      expect(result).toEqual(mockResponse.data);
    });

    it('returns success response with new plan details', async () => {
      const mockResponse = {
        data: {
          success: true,
          new_plan: 'multi_team_v1_yearly',
          status: 'active',
          current_period_end: 1735689600,
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.changePlan('org_test', 'price_yearly');

      expect(result.success).toBe(true);
      expect(result.new_plan).toBe('multi_team_v1_yearly');
      expect(result.status).toBe('active');
    });

    it('propagates API errors', async () => {
      mockPost.mockRejectedValueOnce(new Error('Already on this plan'));

      await expect(
        BillingService.changePlan('org_test', 'price_same')
      ).rejects.toThrow('Already on this plan');
    });
  });

  describe('getOverview', () => {
    it('calls correct endpoint', async () => {
      const mockResponse = {
        data: {
          organization: { id: 'org_123', display_name: 'Test Org' },
          subscription: { id: 'sub_123', status: 'active' },
          plan: { id: 'plan_123', name: 'Team Plus' },
          usage: { members: 5, domains: 2 },
        },
      };
      mockGet.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.getOverview('org_123');

      expect(mockGet).toHaveBeenCalledWith('/billing/api/org/org_123');
      expect(result).toEqual(mockResponse.data);
    });
  });

  describe('createCheckoutSession', () => {
    it('calls correct endpoint with tier and billing cycle', async () => {
      const mockResponse = {
        data: {
          checkout_url: 'https://checkout.stripe.com/session_123',
          session_id: 'cs_123',
        },
      };
      mockPost.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.createCheckoutSession(
        'org_abc',
        'single_team',
        'month'
      );

      expect(mockPost).toHaveBeenCalledWith(
        '/billing/api/org/org_abc/checkout',
        { tier: 'single_team', billing_cycle: 'month' }
      );
      expect(result.checkout_url).toContain('stripe.com');
    });
  });

  describe('listPlans', () => {
    it('calls correct endpoint', async () => {
      const mockResponse = {
        data: {
          plans: [
            { id: 'free_v1', name: 'Free', tier: 'free' },
            { id: 'identity_plus_v1', name: 'Identity Plus', tier: 'single_team' },
          ],
        },
      };
      mockGet.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.listPlans();

      expect(mockGet).toHaveBeenCalledWith('/billing/api/plans');
      expect(result.plans).toHaveLength(2);
    });
  });

  describe('listInvoices', () => {
    it('calls correct endpoint with org extid', async () => {
      const mockResponse = {
        data: {
          invoices: [
            { id: 'inv_123', amount: 2900, status: 'paid' },
            { id: 'inv_456', amount: 2900, status: 'paid' },
          ],
          has_more: false,
        },
      };
      mockGet.mockResolvedValueOnce(mockResponse);

      const result = await BillingService.listInvoices('org_123');

      expect(mockGet).toHaveBeenCalledWith('/billing/api/org/org_123/invoices');
      expect(result.invoices).toHaveLength(2);
      expect(result.has_more).toBe(false);
    });
  });
});
