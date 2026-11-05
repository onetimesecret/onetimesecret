import { incomingSecretRequestSchema } from '@/schemas/api/incoming/requests/incoming-secret';
import { validateRecipientPayloadSchema } from '@/schemas/api/incoming/requests/validate-recipient';
import { responseSchemas as incomingResponses } from '@/schemas/api/incoming/responses/registry';
import * as requests from '@/schemas/api/v3/requests';
import { responseSchemas } from '@/schemas/api/v3/responses/registry';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { captures, type HttpCapture } from './fixtures/v3-http-captures';

const responses: Record<string, z.ZodType> = { ...responseSchemas, ...incomingResponses };
const requestSchemas: Record<string, z.ZodType> = {
  burnSecret: requests.burnSecretRequestSchema,
  concealSecret: requests.concealSecretRequestSchema,
  generateSecret: requests.generateSecretRequestSchema,
  listSecretStatus: requests.listSecretStatusRequestSchema,
  revealSecret: requests.revealSecretRequestSchema,
  updateReceipt: requests.updateReceiptRequestSchema,
  showMultipleReceipts: requests.showMultipleReceiptsRequestSchema,
  receiveFeedback: requests.receiveFeedbackRequestSchema,
  createIncomingSecret: incomingSecretRequestSchema,
  validateRecipient: validateRecipientPayloadSchema,
};

// The archived schema labels describe the broken selection on the old baseline.
// Resolve the two corrected operations from transport metadata, not those labels.
function responseKey(capture: HttpCapture): string {
  if (capture.method === 'GET' && /\/secret\/[^/]+\/status$/.test(capture.path))
    return 'secretStatus';
  if (capture.method === 'PATCH' && /\/receipt\/[^/]+$/.test(capture.path)) return 'updateReceipt';
  return capture.response_schema!;
}

describe('mounted Ruby HTTP captures → producer contracts', () => {
  it('keeps all 41 audited captures, the bearer token grant, and the four previously failing successes', () => {
    if (!process.env.API_V3_SCHEMA_CAPTURE_DIR) expect(captures).toHaveLength(42);
    for (const name of ['status-found', 'status-missing', 'auth-update-memo', 'feedback-actual']) {
      expect(captures.find((capture) => capture.name === name)?.status).toBe(200);
    }
  });

  for (const capture of captures.filter((capture) => capture.status === 200)) {
    it(`${capture.name}: complete HTTP-200 body conforms`, () => {
      const schema = responses[responseKey(capture)];
      expect(schema, `unmapped producer: ${capture.method} ${capture.path}`).toBeDefined();
      const result = schema.safeParse(capture.body);
      expect(result.success, JSON.stringify(result.error?.issues)).toBe(true);
    });
    if (capture.request_schema) {
      it(`${capture.name}: accepted request conforms without losing submitted fields`, () => {
        const schema = requestSchemas[capture.request_schema!];
        expect(schema, `unmapped request: ${capture.request_schema}`).toBeDefined();
        const result = schema!.safeParse(capture.request);
        expect(result.success, JSON.stringify(result.error?.issues)).toBe(true);
        if (result.success) expect(result.data).toEqual(capture.request);
      });
    }
  }

  it('captures contain no session, CSRF, or authorization headers', () => {
    for (const capture of captures) {
      expect(
        Object.keys(capture.headers).some((key) =>
          /cookie|csrf|authorization|shrimp|token/i.test(key)
        )
      ).toBe(false);
    }
  });

  it('does not treat schema-valid rejected historical examples as successes', () => {
    for (const name of ['feedback-documented', 'incoming-create-documented']) {
      const capture = captures.find((capture) => capture.name === name)!;
      expect(capture.status).toBe(422);
      expect(requestSchemas[capture.request_schema!]!.safeParse(capture.request).success).toBe(
        false
      );
    }
  });

  it('retains CSV/array equivalence evidence rather than replacing the working array input', () => {
    const csv = captures.find((capture) => capture.name === 'status-csv')!;
    const array = captures.find((capture) => capture.name === 'status-array')!;
    expect(csv.body.records.map((record: any) => record.identifier).sort()).toEqual(
      array.body.records.map((record: any) => record.identifier).sort()
    );
    expect(csv.body.records).toHaveLength(2);
  });
});
