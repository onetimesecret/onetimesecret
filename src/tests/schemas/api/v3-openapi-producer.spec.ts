import { responseSchemas as v2 } from '@/schemas/api/v2/responses/registry';
import SwaggerParser from '@apidevtools/swagger-parser';
import { createRequire } from 'node:module';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { generateDocument } from '../../../../scripts/openapi/generate-openapi';
import { standardErrorResponses } from '../../../../scripts/openapi/route-config';
import { captures } from '../../contracts/fixtures/v3-http-captures';

const documents = { v2: generateDocument('v2'), v3: generateDocument('v3') };

function operation(version: 'v2' | 'v3', path: string, method: string): any {
  return documents[version].paths[path]?.[method];
}

function response(version: 'v2' | 'v3', path: string, method: string): any {
  return operation(version, path, method).responses['200'].content['application/json'].schema;
}

function request(version: 'v2' | 'v3', path: string): any {
  return operation(version, path, 'post').requestBody.content['application/json'].schema;
}

// Validate generated JSON Schema with the validator already used for OpenAPI
// validation in this repository. This exercises the emitted contract, not just
// registry names or a hand-maintained list of backend fields.
// Resolve SwaggerParser's existing Ajv 8 dependency through its package, not a
// pnpm store path or a new direct dependency. Format checks are out of scope.
const { default: Ajv } = createRequire(import.meta.resolve('@apidevtools/swagger-parser'))(
  'ajv/dist/2020.js'
);
const ajv = new Ajv({ strict: false, validateFormats: false });

function validatePayload(schema: object, value: unknown): boolean {
  return ajv.compile(schema)(value) as boolean;
}

describe('actual OpenAPI generator, without generated output writes', () => {
  for (const version of ['v2', 'v3'] as const) {
    it(`${version}: generated document is structurally valid`, async () => {
      await expect(
        SwaggerParser.validate(structuredClone(documents[version]) as any)
      ).resolves.toBeDefined();
    });

    it(`${version}: shared request corrections and query filters are documented`, () => {
      for (const name of ['conceal', 'generate']) {
        const schema = request(version, `/api/${version}/secret/${name}`).properties.secret;
        expect(schema.required ?? []).not.toContain('kind');
        expect(schema.required ?? []).not.toContain('share_domain');
      }
      const reveal = request(version, `/api/${version}/secret/{identifier}/reveal`);
      const burn = request(version, `/api/${version}/receipt/{identifier}/burn`);
      for (const schema of [reveal, burn]) {
        expect(schema.properties.continue.anyOf.map((entry: any) => entry.type).sort()).toEqual([
          'boolean',
          'string',
        ]);
        expect(schema.properties.passphrase.type).toBe('string');
      }
      expect(
        operation(version, `/api/${version}/receipt/{identifier}`, 'patch').requestBody.content[
          'application/json'
        ].schema.properties.memo.type
      ).toBe('string');
      const list = operation(version, `/api/${version}/receipt/recent`, 'get');
      expect(list.requestBody).toBeUndefined();
      expect(
        list.parameters.map((parameter: any) => [parameter.name, parameter.in, parameter.required])
      ).toEqual([
        ['scope', 'query', false],
        ['domain_extid', 'query', false],
      ]);
      expect(list.responses['422']).toEqual(standardErrorResponses[422]);
    });
  }

  it('V2 response mappings, deprecated aliases, and access metadata are unchanged', () => {
    const json = (schema: z.ZodType) => {
      const result = z.toJSONSchema(schema, { io: 'input', unrepresentable: 'any' });
      delete result.$schema;
      return result;
    };
    for (const [path, method, schema] of [
      ['/api/v2/secret/{identifier}/status', 'get', v2.secretStatus],
      ['/api/v2/receipt/{identifier}', 'patch', v2.receipt],
      ['/api/v2/receipt/{identifier}', 'get', v2.receipt],
      ['/api/v2/receipt/{identifier}/burn', 'post', v2.receipt],
    ] as const) {
      expect(response('v2', path, method)).toEqual(json(schema));
    }
    expect(operation('v2', '/api/v2/private/{identifier}', 'get')?.deprecated).toBe(true);
    expect(operation('v3', '/api/v3/secret/{identifier}/status', 'get').security).toEqual([]);
    // A bearer token is a third credential on the authenticated v3 secret
    // routes (#2427); the exchange itself takes a session or an API key and
    // never a token.
    expect(operation('v3', '/api/v3/receipt/{identifier}', 'patch').security).toEqual([
      { sessionAuth: [] },
      { bearerAuth: [] },
    ]);
    expect(operation('v3', '/api/v3/token', 'post').security).toEqual([
      { sessionAuth: [] },
      { basicAuth: [] },
    ]);
    expect(operation('v3', '/api/v3/version', 'get').security).toEqual([
      { sessionAuth: [] },
      { bearerAuth: [] },
      { basicAuth: [] },
    ]);
    expect(documents.v3.components.securitySchemes.bearerAuth).toMatchObject({
      type: 'http',
      scheme: 'bearer',
    });
    expect(operation('v3', '/api/v3/token', 'post').requestBody).toBeUndefined();
    expect(operation('v2', '/api/v2/secret/{identifier}/status', 'get').security).toEqual([
      { basicAuth: [] },
      {},
    ]);
    expect(documents.v3.info.description).toContain('Subject to change without deprecation.');
    expect(
      Object.keys(documents.v3.paths).every(
        (path) => path.startsWith('/api/v3/') || path.startsWith('/api/incoming/')
      )
    ).toBe(true);
  });

  it('REV-SCHEMA-001: publishes 25 V3 operations without inventing HEAD successes', () => {
    expect(
      Object.values(documents.v3.paths).flatMap((methods) => Object.keys(methods))
    ).toHaveLength(25);
    for (const document of Object.values(documents)) {
      for (const methods of Object.values(document.paths)) {
        expect(methods).not.toHaveProperty('head');
      }
    }
  });

  it('all documented operations have a captured successful producer response', () => {
    const successful = captures.filter((capture) => capture.status === 200);
    for (const [path, methods] of Object.entries(documents.v3.paths)) {
      for (const method of Object.keys(methods)) {
        expect(
          successful.some(
            (capture) =>
              capture.method.toLowerCase() === method &&
              new RegExp(`^${path.replace(/\{[^}]+\}/g, '[^/]+')}$`).test(
                capture.path.split('?')[0]
              )
          ),
          `${method.toUpperCase()} ${path}`
        ).toBe(true);
      }
    }
  });

  it('generated contracts still reject malformed status, memo and acknowledgment payloads', () => {
    expect(
      validatePayload(response('v3', '/api/v3/secret/{identifier}/status', 'get'), {
        record: { state: 'new' },
      })
    ).toBe(false);
    expect(
      validatePayload(response('v3', '/api/v3/receipt/{identifier}', 'patch'), {
        record: { memo: 'partial' },
      })
    ).toBe(false);
    expect(
      validatePayload(response('v3', '/api/v3/feedback', 'post'), { record: {}, details: {} })
    ).toBe(false);
  });

  for (const capture of captures.filter((capture) => capture.status === 200)) {
    it(`${capture.name}: captured HTTP response validates against its generated operation`, async () => {
      const path = capture.path.split('?')[0];
      const template = Object.keys(documents.v3.paths)
        .filter(
          (candidate) =>
            documents.v3.paths[candidate][capture.method.toLowerCase()] &&
            new RegExp(`^${candidate.replace(/\{[^}]+\}/g, '[^/]+')}$`).test(path)
        )
        .sort((a, b) => (a.match(/\{/g)?.length ?? 0) - (b.match(/\{/g)?.length ?? 0))[0];
      expect(template, `missing operation: ${capture.method} ${path}`).toBeDefined();
      const op = operation('v3', template!, capture.method.toLowerCase());
      expect(
        await validatePayload(op.responses['200'].content['application/json'].schema, capture.body)
      ).toBe(true);
      if (capture.request_schema) {
        expect(
          validatePayload(op.requestBody.content['application/json'].schema, capture.request)
        ).toBe(true);
        // Same V2 parser, but version-specific response mappings remain intact.
        const v2Op = operation(
          'v2',
          template!.replace('/api/v3/', '/api/v2/'),
          capture.method.toLowerCase()
        );
        if (v2Op?.requestBody) {
          expect(
            validatePayload(v2Op.requestBody.content['application/json'].schema, capture.request)
          ).toBe(true);
        }
      }
    });
  }

  it('does not publish the rejected feedback message/email example as valid', () => {
    const capture = captures.find((capture) => capture.name === 'feedback-documented')!;
    expect(capture.status).toBe(422);
    expect(validatePayload(request('v3', '/api/v3/feedback'), capture.request)).toBe(false);
  });

  it('Incoming uses the nested transport schema, without publishing content as the body', async () => {
    const schema = request('v3', '/api/incoming/secret');
    expect(
      await validatePayload(schema, { secret: { secret: 'synthetic', recipient: 'digest' } })
    ).toBe(true);
    expect(await validatePayload(schema, { secret: 'synthetic', recipient: 'digest' })).toBe(false);
  });
});
