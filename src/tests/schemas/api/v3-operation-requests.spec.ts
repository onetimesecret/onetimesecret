import * as incoming from '@/schemas/api/incoming/requests/incoming-secret';
import * as requests from '@/schemas/api/v3/requests';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

describe('V3 operation requests reflect producer parsing', () => {
  for (const schema of [requests.revealSecretRequestSchema, requests.burnSecretRequestSchema]) {
    it.each([true, false, 'true', 'false', 'anything'])(
      'preserves confirmation %j (only true/"true" commits)',
      (value) => {
        expect(schema.parse({ continue: value, passphrase: 'synthetic test passphrase' })).toEqual({
          continue: value,
          passphrase: 'synthetic test passphrase',
        });
      }
    );
    it.each([1, null, [], {}])('does not document malformed confirmation %j', (value) => {
      expect(schema.safeParse({ continue: value }).success).toBe(false);
    });
  }

  it('leaves creation defaults to the server without synthesizing client values', () => {
    expect(
      requests.concealSecretRequestSchema.parse({ secret: { secret: 'synthetic value' } })
    ).toEqual({ secret: { secret: 'synthetic value' } });
    expect(requests.generateSecretRequestSchema.parse({ secret: {} })).toEqual({ secret: {} });
    for (const schema of [
      requests.concealSecretRequestSchema,
      requests.generateSecretRequestSchema,
    ]) {
      const json = z.toJSONSchema(schema, { io: 'input' });
      expect(JSON.stringify(json)).not.toContain('"default"');
    }
  });

  it('documents msg/tz, not the rejected feedback message/email body', () => {
    expect(
      requests.receiveFeedbackRequestSchema.parse({ msg: 'synthetic feedback', tz: 'UTC' })
    ).toEqual({ msg: 'synthetic feedback', tz: 'UTC' });
    expect(requests.receiveFeedbackRequestSchema.safeParse({ msg: '' }).success).toBe(false);
    expect(
      requests.receiveFeedbackRequestSchema.safeParse({
        message: 'not consumed',
        email: 'test@example.com',
      }).success
    ).toBe(false);
  });

  it('preserves empty and oversized memos; sanitization/truncation belongs to Ruby', () => {
    for (const memo of ['', 'updated memo', 'm'.repeat(501)]) {
      expect(requests.updateReceiptRequestSchema.parse({ memo })).toEqual({ memo });
    }
    expect(requests.updateReceiptRequestSchema.parse({})).toEqual({});
    expect(requests.updateReceiptRequestSchema.safeParse({ memo: {} }).success).toBe(false);
  });

  for (const schema of [
    requests.listSecretStatusRequestSchema,
    requests.showMultipleReceiptsRequestSchema,
  ]) {
    it.each([{ identifiers: ['first', 'second'] }, { identifiers: 'first,second' }])(
      'preserves batch identifiers %j',
      ({ identifiers }) => {
        expect(schema.parse({ identifiers })).toEqual({ identifiers });
      }
    );
    it('rejects nested identifier objects', () => {
      expect(schema.safeParse({ identifiers: { first: 'second' } }).success).toBe(false);
    });
  }

  it('documents scalar receipt query filters without inventing a closed scope enum', () => {
    for (const scope of ['org', 'domain', 'nonsense']) {
      expect(
        requests.listReceiptsRequestSchema.parse({ scope, domain_extid: 'domain-id' })
      ).toEqual({ scope, domain_extid: 'domain-id' });
    }
    expect(requests.listReceiptsRequestSchema.safeParse({ scope: ['org'] }).success).toBe(false);
  });

  it('separates Incoming transport wrapping from the existing frontend content schema', () => {
    const content = { secret: 'synthetic incoming value', recipient: 'synthetic-digest', memo: '' };
    expect(incoming.incomingSecretPayloadSchema.parse(content)).toEqual(content);
    expect(
      incoming.incomingSecretPayloadSchema.parse({ secret: 'value', recipient: 'digest' }).memo
    ).toBe('');
    const schema = incoming.incomingSecretRequestSchema;
    expect(schema).toBeDefined();
    expect(schema.parse({ secret: content })).toEqual({ secret: content });
    expect(schema.safeParse(content).success).toBe(false);
  });
});
