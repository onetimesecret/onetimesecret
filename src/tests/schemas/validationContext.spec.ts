import { BrowserClient, Scope, defaultStackParser } from '@sentry/browser';
import type { Envelope } from '@sentry/core';
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest';

import { allSchemas, checkPayload, closest } from '@/schemas/check';
import { organizationSchema } from '@/schemas/shapes/organizations/organization';
import { schemaDiagnosticsEnabled, withoutSchemaDiagnostics } from '@/schemas/validationContext';
import * as diagnostics from '@/services/diagnostics.service';

describe('schema validation context', () => {
  it('returns the callback result and keeps diagnostics suppressed across nested checks', () => {
    const value = { checked: true };
    expect(schemaDiagnosticsEnabled()).toBe(true);
    const result = withoutSchemaDiagnostics(() => {
      expect(schemaDiagnosticsEnabled()).toBe(false);
      expect(
        withoutSchemaDiagnostics(() => {
          expect(schemaDiagnosticsEnabled()).toBe(false);
          return value;
        })
      ).toBe(value);
      expect(schemaDiagnosticsEnabled()).toBe(false);
      return value;
    });
    expect(result).toBe(value);
    expect(schemaDiagnosticsEnabled()).toBe(true);
  });

  it('restores the enclosing state after an inner throw and the default state after an outer throw', () => {
    const error = new Error('check failed');
    expect(() =>
      withoutSchemaDiagnostics(() => {
        expect(() =>
          withoutSchemaDiagnostics(() => {
            expect(schemaDiagnosticsEnabled()).toBe(false);
            throw error;
          })
        ).toThrow(error);
        expect(schemaDiagnosticsEnabled()).toBe(false);
        throw error;
      })
    ).toThrow(error);
    expect(schemaDiagnosticsEnabled()).toBe(true);
  });

  it('restores synchronously when the callback returns a Promise', async () => {
    const result = withoutSchemaDiagnostics(() => {
      expect(schemaDiagnosticsEnabled()).toBe(false);
      return Promise.resolve().then(() => schemaDiagnosticsEnabled());
    });
    expect(schemaDiagnosticsEnabled()).toBe(true);
    expect(await result).toBe(true);
  });
});

describe('organization diagnostics during arbitrary JSON checks (CHK-002)', () => {
  let client: BrowserClient;
  let envelopes: Envelope[];
  let warnings: MockInstance<typeof console.warn>;
  let captures: MockInstance<typeof diagnostics.captureMessage>;

  beforeEach(() => {
    envelopes = [];
    client = new BrowserClient({
      dsn: 'https://public@example.test/1',
      integrations: [],
      stackParser: defaultStackParser,
      transport: () => ({
        send: (envelope) => {
          envelopes.push(envelope);
          return Promise.resolve({ statusCode: 200 });
        },
        flush: () => Promise.resolve(true),
      }),
    });
    const scope = new Scope();
    scope.setClient(client);
    client.init();
    diagnostics.initDiagnostics(client, scope);
    warnings = vi.spyOn(console, 'warn').mockImplementation(() => {});
    captures = vi.spyOn(diagnostics, 'captureMessage');
  });

  afterEach(async () => {
    try {
      await client.close(1000);
    } finally {
      vi.restoreAllMocks();
    }
  });

  it.each(['checkPayload', 'closest'] as const)(
    '%s suppresses warnings and transport events without poisoning ordinary parse dedupe',
    async (operation) => {
      const privateMarker = `CHK-002-private-pasted-entitlement-${operation}`;
      const input = {
        objid: 'organization-test',
        extid: 'on-organization-test',
        display_name: 'Organization test',
        description: null,
        contact_email: null,
        is_default: false,
        planid: 'free_v1',
        created: 1700000000,
        updated: 1700000000,
        entitlements: [privateMarker],
      };
      const schemas = allSchemas();
      expect(schemas.get('shapes/organization')).toBe(organizationSchema);
      expect(diagnostics.isDiagnosticsEnabled()).toBe(true);

      withoutSchemaDiagnostics(() => {
        if (operation === 'checkPayload') {
          const result = checkPayload(organizationSchema, input);
          expect(result.success).toBe(true);
          expect(result.issueCount).toBe(0);
        } else {
          const candidates = closest(input, schemas, schemas.size);
          expect(candidates).toContainEqual(
            expect.objectContaining({ name: 'shapes/organization', issues: 0 })
          );
        }
      });

      expect(schemaDiagnosticsEnabled()).toBe(true);
      expect(await client.flush(1000)).toBe(true);
      expect(warnings).not.toHaveBeenCalled();
      expect(captures).not.toHaveBeenCalled();
      expect(envelopes).toEqual([]);
      expect(JSON.stringify(envelopes)).not.toContain(privateMarker);

      const parsed = organizationSchema.parse(input);
      expect(parsed.entitlements).toEqual([privateMarker]);
      expect(parsed.created).toBeInstanceOf(Date);
      expect(warnings).toHaveBeenCalledExactlyOnceWith(
        `[entitlements] Unfamiliar entitlement: "${privateMarker}"`
      );
      expect(captures).toHaveBeenCalledExactlyOnceWith(
        `Unfamiliar entitlement: "${privateMarker}"`,
        { level: 'warning', tags: { entitlement: privateMarker } }
      );
      expect(await client.flush(1000)).toBe(true);
      expect(envelopes).toHaveLength(1);
      expect(JSON.stringify(envelopes)).toContain(privateMarker);

      organizationSchema.parse(input);
      expect(await client.flush(1000)).toBe(true);
      expect(warnings).toHaveBeenCalledTimes(1);
      expect(captures).toHaveBeenCalledTimes(1);
      expect(envelopes).toHaveLength(1);
    }
  );
});
