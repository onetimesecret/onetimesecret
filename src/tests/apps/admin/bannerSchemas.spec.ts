// src/tests/apps/admin/bannerSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelBannerResponseSchema,
  colonelBannerSetResponseSchema,
  colonelBannerClearResponseSchema,
} from '@/schemas/api/internal/responses/colonel-banner';

/**
 * Zod tripwire (CONTRACT 3) for the Broadcast Banner screen (#41). All three
 * payloads are shaped exactly as the live logic classes emit them — verified
 * against apps/api/colonel/logic/colonel/{get,set,clear}_banner.rb (which delegate
 * to Onetime::Operations::{Get,Set,Clear}Banner). A backend drift fails here
 * rather than silently breaking the screen.
 */

describe('colonelBannerResponseSchema (GetBanner)', () => {
  it('parses a live persistent banner (ttl null)', () => {
    const payload = {
      shrimp: '',
      record: { content: '<a href="/status">Notice</a>', ttl: null, active: true },
      details: { key: 'global_banner', database: 0 },
    };
    const result = colonelBannerResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.active).toBe(true);
    expect(result.data.record.ttl).toBeNull();
  });

  it('parses an expiring banner (ttl number) and the empty state (content null)', () => {
    expect(
      colonelBannerResponseSchema.safeParse({
        shrimp: '',
        record: { content: 'temp', ttl: 3600, active: true },
        details: { key: 'global_banner', database: 0 },
      }).success
    ).toBe(true);

    expect(
      colonelBannerResponseSchema.safeParse({
        shrimp: '',
        record: { content: null, ttl: null, active: false },
        details: { key: 'global_banner', database: 0 },
      }).success
    ).toBe(true);
  });

  it('rejects a record missing the active flag (contract drift)', () => {
    const payload = {
      record: { content: 'x', ttl: null },
      details: { key: 'global_banner', database: 0 },
    };
    expect(colonelBannerResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('colonelBannerSetResponseSchema (SetBanner ack)', () => {
  it('validates the publish ack', () => {
    const payload = {
      shrimp: '',
      record: { content: 'New notice', ttl: null, active: true },
      details: { message: 'Broadcast banner published' },
    };
    const result = colonelBannerSetResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details.message).toBe('Broadcast banner published');
  });

  it('rejects a set ack missing details.message', () => {
    const payload = {
      record: { content: 'x', ttl: null, active: true },
      details: {},
    };
    expect(colonelBannerSetResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('colonelBannerClearResponseSchema (ClearBanner ack)', () => {
  it('validates the clear ack (cleared true/false)', () => {
    expect(
      colonelBannerClearResponseSchema.safeParse({
        shrimp: '',
        record: { cleared: true, active: false },
        details: { message: 'Broadcast banner cleared' },
      }).success
    ).toBe(true);

    expect(
      colonelBannerClearResponseSchema.safeParse({
        shrimp: '',
        record: { cleared: false, active: false },
        details: { message: 'No banner was set' },
      }).success
    ).toBe(true);
  });

  it('rejects a clear ack missing the cleared flag', () => {
    const payload = { record: { active: false }, details: { message: 'ok' } };
    expect(colonelBannerClearResponseSchema.safeParse(payload).success).toBe(false);
  });
});
