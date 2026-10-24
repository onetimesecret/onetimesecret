import { responseSchemas } from '@/schemas/api/v3/responses/registry';
import { receiptBaseSchema } from '@/schemas/shapes/v3/receipt';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

const schemas = responseSchemas as Record<string, z.ZodType>;
const body = (name: string) => JSON.parse(readFileSync(new URL(`../../contracts/fixtures/api-v3-http/${name}.json`, import.meta.url), 'utf8')).body;

describe('operation-specific V3 producer boundaries', () => {
  it('requires complete found status and expiration, without full-secret UI details', () => {
    const found = body('status-found');
    expect(schemas.secretStatus.safeParse(found).success).toBe(true);
    expect(schemas.secret.safeParse(found).success).toBe(false);
    expect(schemas.secretStatus.safeParse({ record: found.record }).success).toBe(false);
    expect(schemas.secretStatus.safeParse({ record: found.record, details: {} }).success).toBe(false);
    expect(schemas.secretStatus.safeParse({ record: { state: 'new' }, details: found.details }).success).toBe(false);
    expect(schemas.secretStatus.safeParse({ ...found, details: { current_expiration: null } }).success).toBe(true);
  });

  it('accepts only the bare unknown branch, not an incomplete found record', () => {
    expect(schemas.secretStatus.parse(body('status-missing'))).toEqual({ record: { state: 'unknown' } });
    for (const record of [{}, { state: 'new' }, { state: 'unknown', identifier: 'partial' }]) {
      expect(schemas.secretStatus.safeParse({ record }).success).toBe(false);
    }
  });

  it('requires current producer display_type instead of applying reader fallback', () => {
    const found = body('status-found');
    for (const display_type of [undefined, 'future-type', null]) {
      expect(schemas.secretStatus.safeParse({ ...found, record: { ...found.record, display_type } }).success).toBe(false);
    }
  });

  it('describes memo safe_dump, not computed URLs, expiration, or reveal details', () => {
    const memo = body('auth-update-memo');
    expect(schemas.updateReceipt.parse(memo)).toEqual(memo);
    expect(schemas.receipt.safeParse(memo).success).toBe(false);
    const json = z.toJSONSchema(schemas.updateReceipt, { io: 'input' });
    const properties = (json.properties!.record as { properties: Record<string, unknown> }).properties;
    for (const field of ['share_url', 'burn_url', 'receipt_url', 'share_path', 'burn_path', 'receipt_path', 'expiration', 'expiration_in_seconds', 'natural_expiration']) {
      expect(properties).not.toHaveProperty(field);
      expect(memo.record).not.toHaveProperty(field);
    }
    expect(schemas.updateReceipt.safeParse({ record: { identifier: memo.record.identifier, memo: 'incomplete' } }).success).toBe(false);
    expect(schemas.updateReceipt.safeParse({ ...memo, details: { secret_value: 'should not be here' } }).success).toBe(false);
  });

  it('keeps producer recipients narrow without narrowing the tolerant model reader', () => {
    const memo = body('auth-update-memo');
    const record = { ...memo.record, recipients: 'legacy@example.com' };
    expect(receiptBaseSchema.safeParse(record).success).toBe(true);
    expect(schemas.updateReceipt.safeParse({ record }).success).toBe(false);
    expect(schemas.updateReceipt.safeParse({ record: { ...record, recipients: [] } }).success).toBe(false);
    expect(schemas.updateReceipt.safeParse({ record: { ...record, recipients: ['o***@example.com'] } }).success).toBe(true);
  });

  it('models feedback as an acknowledgment, not a stored feedback entity', () => {
    const feedback = body('feedback-actual');
    expect(schemas.feedback.parse(feedback)).toEqual(feedback);
    expect(schemas.feedback.safeParse({ record: {} }).success).toBe(false);
    expect(schemas.feedback.safeParse({ record: {}, details: {} }).success).toBe(false);
    expect(schemas.feedback.safeParse({ record: { msg: 'entity', stamp: 1 }, details: { received: true } }).success).toBe(false);
  });

  it('rejects accidental plaintext or internal fields in these producer records', () => {
    for (const [key, name] of [['secretStatus', 'status-found'], ['updateReceipt', 'auth-update-memo'], ['feedback', 'feedback-actual']]) {
      const payload = body(name);
      for (const field of ['secret_value', 'value', 'passphrase', 'encryption_key']) {
        expect(schemas[key].safeParse({ ...payload, record: { ...payload.record, [field]: 'unexpected' } }).success).toBe(false);
      }
    }
  });
});
