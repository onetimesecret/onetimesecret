// src/tests/scripts/generate-sentry-scrub-patterns.spec.ts
//
// Unit tests for `validateSensitiveRoute`, the structural validator used by
// the Sentry scrub-patterns generator. Exercises both guard branches:
//
//   1. Missing-param: a `sensitive=name` annotation that references a token
//      not present in the route path.
//   2. Zero-capture: a `sensitive=true` annotation on a path with no :param
//      tokens (the resulting regex would have zero capture groups).
//
// These cases are non-trivial to reproduce through the full pipeline because
// they require routes.txt drift. Testing the validator directly keeps the
// feedback loop fast and the coverage explicit.
//
// Run:
//   pnpm test src/tests/scripts/generate-sentry-scrub-patterns.spec.ts

import { describe, it, expect } from 'vitest';

import { validateSensitiveRoute } from '../../../scripts/generate-sentry-scrub-patterns';

describe('validateSensitiveRoute', () => {
  describe('happy paths (does not throw)', () => {
    it('accepts a valid named-param spec where :foo is in the path', () => {
      expect(() =>
        validateSensitiveRoute('GET', '/api/v1/secret/:foo', ['foo'], new Set(['foo']))
      ).not.toThrow();
    });

    it('accepts sensitive=true on a path with one :param', () => {
      expect(() =>
        validateSensitiveRoute('GET', '/api/v1/secret/:key', ['key'], true)
      ).not.toThrow();
    });

    it('accepts sensitive=foo,bar when both :foo and :bar are in the path', () => {
      expect(() =>
        validateSensitiveRoute(
          'POST',
          '/api/v1/secret/:foo/receipt/:bar',
          ['foo', 'bar'],
          new Set(['foo', 'bar'])
        )
      ).not.toThrow();
    });

    it('accepts sensitive=key on a path /foo/:key (named capture happy path)', () => {
      expect(() =>
        validateSensitiveRoute('GET', '/foo/:key', ['key'], new Set(['key']))
      ).not.toThrow();
    });
  });

  describe('missing-param throw', () => {
    it('throws when sensitive=foo but :foo is not in the path', () => {
      expect(() =>
        validateSensitiveRoute(
          'GET',
          '/api/v1/status/:other',
          ['other'],
          new Set(['foo'])
        )
      ).toThrow(/GET.*\/api\/v1\/status\/:other.*foo/);
    });

    it('error message names the HTTP method, full path, and missing param', () => {
      let caught: Error | null = null;
      try {
        validateSensitiveRoute(
          'DELETE',
          '/api/v2/receipt/:id',
          ['id'],
          new Set(['token'])
        );
      } catch (e) {
        caught = e as Error;
      }
      expect(caught).not.toBeNull();
      const message = caught!.message;
      expect(message).toContain('DELETE');
      expect(message).toContain('/api/v2/receipt/:id');
      expect(message).toContain('token');
    });

    it('throws naming `bar` specifically when sensitive=foo,bar and :foo exists but :bar does not', () => {
      let caught: Error | null = null;
      try {
        validateSensitiveRoute(
          'POST',
          '/api/v1/secret/:foo',
          ['foo'],
          new Set(['foo', 'bar'])
        );
      } catch (e) {
        caught = e as Error;
      }
      expect(caught).not.toBeNull();
      const message = caught!.message;
      expect(message).toContain('POST');
      expect(message).toContain('/api/v1/secret/:foo');
      // The validator should flag the missing `bar` by name, not the
      // already-present `foo`.
      expect(message).toMatch(/:bar is not a path parameter/);
    });
  });

  describe('zero-capture throw', () => {
    it('throws when sensitive=true is applied to a path with no :param tokens', () => {
      let caught: Error | null = null;
      try {
        validateSensitiveRoute('GET', '/api/v1/status', [], true);
      } catch (e) {
        caught = e as Error;
      }
      expect(caught).not.toBeNull();
      const message = caught!.message;
      expect(message).toContain('GET');
      expect(message).toContain('/api/v1/status');
      expect(message).toMatch(/0 capture groups/);
    });

    it('error names the HTTP method and full path', () => {
      expect(() =>
        validateSensitiveRoute('POST', '/api/v2/health', [], true)
      ).toThrow(/POST.*\/api\/v2\/health/);
    });

    it('does not throw on sensitive=true with at least one :param', () => {
      expect(() =>
        validateSensitiveRoute('GET', '/api/v1/secret/:identifier', ['identifier'], true)
      ).not.toThrow();
    });
  });
});
