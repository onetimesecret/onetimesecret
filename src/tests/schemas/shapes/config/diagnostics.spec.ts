// src/tests/schemas/shapes/config/diagnostics.spec.ts
//
// Coverage for the diagnostics shape — the top-level `enabled` flag and
// the three nested sentry trees (defaults / backend / frontend). The
// frontend tree has the extra `trackComponents` default the other two
// lack; this file pins that asymmetry.

import { describe, it, expect } from 'vitest';
import {
  diagnosticsSchema,
  diagnosticsSentryDefaultsSchema,
  diagnosticsSentryFrontendSchema,
} from '@/schemas/contracts/config/section/diagnostics';
import {
  diagnosticsShape,
  diagnosticsSentryShape,
  diagnosticsSentryDefaultsShape,
  diagnosticsSentryBackendShape,
  diagnosticsSentryFrontendShape,
} from '@/schemas/shapes/config/section/diagnostics';

describe('diagnosticsShape — top-level defaults', () => {
  it('enabled defaults to false', () => {
    expect(diagnosticsShape.parse({}).enabled).toBe(false);
  });

  it('leaves the sentry sub-tree undefined when omitted', () => {
    expect(diagnosticsShape.parse({}).sentry).toBeUndefined();
  });
});

describe('diagnosticsSentry*Shape — logErrors default', () => {
  it.each([
    ['defaults', diagnosticsSentryDefaultsShape],
    ['backend', diagnosticsSentryBackendShape],
    ['frontend', diagnosticsSentryFrontendShape],
  ])('%s shape defaults logErrors to true', (_label, shape) => {
    expect(shape.parse({}).logErrors).toBe(true);
  });

  it('frontend shape also defaults trackComponents to true', () => {
    expect(diagnosticsSentryFrontendShape.parse({}).trackComponents).toBe(true);
  });

  it.each([
    ['defaults', diagnosticsSentryDefaultsSchema],
    ['frontend', diagnosticsSentryFrontendSchema],
  ])('contract leaves logErrors undefined for %s', (_label, schema) => {
    expect((schema.parse({}) as { logErrors?: boolean }).logErrors).toBeUndefined();
  });
});

describe('diagnosticsSentryShape — composed sub-trees', () => {
  it('applies logErrors defaults to every sub-tree when each is provided empty', () => {
    const result = diagnosticsSentryShape.parse({ defaults: {}, backend: {}, frontend: {} });
    expect(result.defaults?.logErrors).toBe(true);
    expect(result.backend?.logErrors).toBe(true);
    expect(result.frontend?.logErrors).toBe(true);
    expect(result.frontend?.trackComponents).toBe(true);
  });

  it('preserves a caller-supplied dsn over the implicit defaults', () => {
    const result = diagnosticsSentryShape.parse({
      defaults: { dsn: 'https://sentry.example/1' },
    });
    expect(result.defaults?.dsn).toBe('https://sentry.example/1');
    expect(result.defaults?.logErrors).toBe(true);
  });
});

describe('diagnosticsShape — composed', () => {
  it('applies sentry defaults when caller passes empty sentry sub-objects', () => {
    const result = diagnosticsShape.parse({
      enabled: true,
      sentry: { defaults: {}, backend: {}, frontend: {} },
    });
    expect(result.enabled).toBe(true);
    expect(result.sentry?.defaults?.logErrors).toBe(true);
    expect(result.sentry?.frontend?.trackComponents).toBe(true);
  });

  it('contract leaves enabled undefined', () => {
    expect(diagnosticsSchema.parse({}).enabled).toBeUndefined();
  });
});
