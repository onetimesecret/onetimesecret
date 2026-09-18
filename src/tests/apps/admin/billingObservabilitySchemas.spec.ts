// src/tests/apps/admin/billingObservabilitySchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelPendingFederatedSubscriptionsResponseSchema,
  colonelWebhookEventDetailResponseSchema,
  colonelWebhookEventsResponseSchema,
} from '@/schemas/api/internal/responses/colonel-billing';
import { responseSchemas } from '@/schemas/api/internal/responses/registry';

const pagination = { page: 1, per_page: 50, total_count: 1, total_pages: 1 };

describe('billing observability response contracts', () => {
  it('parses the paginated webhook list and safe detail allow-list', () => {
    const list = colonelWebhookEventsResponseSchema.parse({
      shrimp: '',
      record: {},
      details: {
        events: [
          {
            event_id: 'evt_123',
            event_type: 'customer.subscription.updated',
            processing_status: 'failed',
            processing_outcome: 'Failed',
            received_at: 1_780_000_000,
            processed_at: null,
            attempt_count: 2,
            retryable: true,
          },
        ],
        pagination,
      },
    });
    const detail = colonelWebhookEventDetailResponseSchema.parse({
      shrimp: '',
      record: {
        ...list.details?.events[0],
        event_payload: { must_not_render: true },
      },
      details: {
        api_version: '2026-01-01',
        livemode: true,
        stripe_created_at: 1_779_999_000,
        pending_webhooks: 0,
        last_attempt_at: 1_780_000_030,
        retryable: true,
        max_attempts_reached: false,
        circuit_retry_at: null,
        circuit_retry_count: 0,
        error_present: true,
      },
    });

    expect(list.details?.events[0].event_id).toBe('evt_123');
    expect(detail.record).not.toHaveProperty('event_payload');
    expect(responseSchemas.colonelWebhookEvents).toBe(colonelWebhookEventsResponseSchema);
    expect(responseSchemas.colonelWebhookEventDetail).toBe(colonelWebhookEventDetailResponseSchema);
  });

  it('requires an explicit source-webhook correlation state for pending rows', () => {
    const parsed = colonelPendingFederatedSubscriptionsResponseSchema.parse({
      shrimp: '',
      record: {},
      details: {
        subscriptions: [
          {
            subscription_status: 'active',
            planid: null,
            region: 'eu',
            received_at: 1_780_000_000,
            source_webhook: {
              state: 'expired',
              processing_status: null,
              outcome: null,
            },
          },
        ],
        pagination: { ...pagination, capped: true },
      },
    });

    expect(parsed.details?.subscriptions[0].planid).toBeNull();
    expect(parsed.details?.subscriptions[0].source_webhook.state).toBe('expired');

    const noCorrelation = colonelPendingFederatedSubscriptionsResponseSchema.safeParse({
      record: {},
      details: {
        subscriptions: [
          {
            subscription_status: 'active',
            planid: 'pro_monthly',
            region: 'us',
            received_at: 1_780_000_001,
            source_webhook: {
              state: 'no_correlation',
              processing_status: null,
              outcome: null,
            },
          },
        ],
        pagination,
      },
    });
    expect(noCorrelation.success).toBe(true);
    expect(responseSchemas.colonelPendingFederatedSubscriptions).toBe(
      colonelPendingFederatedSubscriptionsResponseSchema
    );
  });

  it('rejects a pending row whose missing webhook correlation is ambiguous', () => {
    expect(
      colonelPendingFederatedSubscriptionsResponseSchema.safeParse({
        record: {},
        details: { subscriptions: [{ planid: null }], pagination },
      }).success
    ).toBe(false);
  });

  it('rejects pending rows that include fields absent from the endpoint contract', () => {
    const response = {
      record: {},
      details: {
        subscriptions: [
          {
            subscription_status: 'active',
            planid: 'pro_monthly',
            region: 'us',
            received_at: 1_780_000_000,
            source_region: 'us-east-1',
            source_event: 'customer.subscription.updated',
            source_event_id: 'evt_123',
            email_hash: 'must-not-cross-the-api-boundary',
            source_webhook: {
              state: 'available',
              processing_status: 'success',
              outcome: 'Processed',
            },
          },
        ],
        pagination,
      },
    };

    expect(colonelPendingFederatedSubscriptionsResponseSchema.safeParse(response).success).toBe(
      false
    );
  });
});
