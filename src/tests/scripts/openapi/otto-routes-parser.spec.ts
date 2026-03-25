// src/tests/scripts/openapi/otto-routes-parser.spec.ts

import { writeFileSync, mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  getAuthRequirements,
  parseRoutesFile,
  type OttoRoute,
} from '@/scripts/openapi/otto-routes-parser';

/**
 * Helper to build an OttoRoute with the given params.
 * Omits fields irrelevant to the test under focus.
 */
function makeRoute(params: Record<string, string>): OttoRoute {
  return {
    method: 'GET',
    path: '/test',
    handler: 'TestHandler',
    params,
    raw: 'GET /test TestHandler',
    lineNumber: 1,
  };
}

describe('otto-routes-parser', () => {
  // ─── getAuthRequirements ───────────────────────────────────────

  describe('getAuthRequirements', () => {
    it('reads openapi_auth when auth is absent (V1 pattern)', () => {
      const route = makeRoute({ openapi_auth: 'basic,anonymous' });
      const result = getAuthRequirements(route);

      // V1 tokens are normalized: basic→basicauth, anonymous→noauth
      expect(result).toEqual({
        required: true,
        schemes: ['basicauth', 'noauth'],
      });
    });

    it('reads auth when present (V2+ pattern)', () => {
      const route = makeRoute({ auth: 'sessionauth,basicauth' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: true,
        schemes: ['sessionauth', 'basicauth'],
      });
    });

    it('auth takes precedence over openapi_auth when both present', () => {
      const route = makeRoute({
        auth: 'sessionauth',
        openapi_auth: 'basic,anonymous',
      });
      const result = getAuthRequirements(route);

      // auth= wins because of || short-circuit order
      expect(result).toEqual({
        required: true,
        schemes: ['sessionauth'],
      });
    });

    it('returns required: false with empty schemes when neither attribute present', () => {
      const route = makeRoute({});
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: false,
        schemes: [],
      });
    });

    it('returns required: false when auth is noauth', () => {
      const route = makeRoute({ auth: 'noauth' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: false,
        schemes: [],
      });
    });

    it('returns required: false when openapi_auth is noauth', () => {
      const route = makeRoute({ openapi_auth: 'noauth' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: false,
        schemes: [],
      });
    });

    it('extracts role from openapi_auth containing role:colonel', () => {
      const route = makeRoute({ openapi_auth: 'basic,role:colonel' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: true,
        schemes: ['basicauth'],
        role: 'colonel',
      });
    });

    it('handles single openapi_auth scheme', () => {
      const route = makeRoute({ openapi_auth: 'basic' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: true,
        schemes: ['basicauth'],
      });
    });

    // Tests for separate role= param (as used in colonel routes)
    it('extracts role from separate role param with auth=sessionauth', () => {
      const route = makeRoute({ auth: 'sessionauth', role: 'colonel' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: true,
        schemes: ['sessionauth'],
        role: 'colonel',
      });
    });

    it('ignores role param when no auth is specified', () => {
      // Edge case: role param but no auth (role is meaningless without auth)
      // This is correct behavior - role enforcement requires auth first
      const route = makeRoute({ role: 'colonel' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: false,
        schemes: [],
      });
    });

    it('role:X in auth takes precedence over separate role param', () => {
      // If both role:X and role= are present, role:X should win (per implementation)
      const route = makeRoute({
        auth: 'sessionauth,role:admin',
        role: 'colonel',
      });
      const result = getAuthRequirements(route);

      // role:admin in auth string takes precedence
      expect(result).toEqual({
        required: true,
        schemes: ['sessionauth'],
        role: 'admin',
      });
    });

    it('extracts role from auth param containing role:colonel', () => {
      const route = makeRoute({ auth: 'sessionauth,role:colonel' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: true,
        schemes: ['sessionauth'],
        role: 'colonel',
      });
    });

    it('handles multiple auth schemes with role', () => {
      const route = makeRoute({ auth: 'sessionauth,basicauth', role: 'colonel' });
      const result = getAuthRequirements(route);

      expect(result).toEqual({
        required: true,
        schemes: ['sessionauth', 'basicauth'],
        role: 'colonel',
      });
    });
  });

  // ─── parseRouteLine (tested via parseRoutesFile) ───────────────

  describe('parseRouteLine via parseRoutesFile', () => {
    let tmpDir: string;

    beforeEach(() => {
      tmpDir = mkdtempSync(join(tmpdir(), 'otto-routes-test-'));
    });

    afterEach(() => {
      rmSync(tmpDir, { recursive: true, force: true });
    });

    function parseLines(content: string) {
      const filePath = join(tmpDir, 'routes.txt');
      writeFileSync(filePath, content, 'utf-8');
      return parseRoutesFile(filePath);
    }

    it('stores openapi_auth as params.openapi_auth', () => {
      const { routes } = parseLines(
        'GET /status V1::Controllers::Index#status openapi_auth=basic,anonymous response=json'
      );

      expect(routes).toHaveLength(1);
      expect(routes[0].params.openapi_auth).toBe('basic,anonymous');
      expect(routes[0].params.auth).toBeUndefined();
    });

    it('stores auth as params.auth', () => {
      const { routes } = parseLines(
        'GET /receipt/recent V2::Logic::Secrets::ListReceipts response=json auth=basicauth,noauth'
      );

      expect(routes).toHaveLength(1);
      expect(routes[0].params.auth).toBe('basicauth,noauth');
      expect(routes[0].params.openapi_auth).toBeUndefined();
    });

    it('parses multiple key=value parameters including openapi_auth', () => {
      const { routes } = parseLines(
        'POST /share V1::Controllers::Index#share openapi_auth=basic,anonymous content=form response=json'
      );

      expect(routes).toHaveLength(1);
      const r = routes[0];
      expect(r.params.openapi_auth).toBe('basic,anonymous');
      expect(r.params.content).toBe('form');
      expect(r.params.response).toBe('json');
    });

    it('skips comment and empty lines', () => {
      const content = [
        '# This is a comment',
        '',
        'GET /status Handler openapi_auth=basic response=json',
        '  # indented comment',
        '',
      ].join('\n');

      const { routes } = parseLines(content);
      expect(routes).toHaveLength(1);
      expect(routes[0].path).toBe('/status');
    });

    it('assigns correct line numbers', () => {
      const content = [
        '# comment on line 1',
        'GET /a Handler openapi_auth=basic',
        '',
        'POST /b Handler auth=sessionauth',
      ].join('\n');

      const { routes } = parseLines(content);
      expect(routes).toHaveLength(2);
      expect(routes[0].lineNumber).toBe(2);
      expect(routes[1].lineNumber).toBe(4);
    });
  });

  // ─── V1 routes.txt integration ────────────────────────────────

  describe('V1 routes.txt integration', () => {
    const v1RoutesPath = join(
      process.cwd(),
      'apps',
      'api',
      'v1',
      'routes.txt'
    );

    let v1Routes: OttoRoute[];

    beforeEach(() => {
      const parsed = parseRoutesFile(v1RoutesPath);
      v1Routes = parsed.routes;
    });

    it('parses at least one route from V1 routes.txt', () => {
      expect(v1Routes.length).toBeGreaterThan(0);
    });

    it('all V1 routes use openapi_auth, not auth', () => {
      for (const route of v1Routes) {
        expect(route.params).not.toHaveProperty('auth');
        expect(route.params).toHaveProperty('openapi_auth');
      }
    });

    it('getAuthRequirements works for every V1 route', () => {
      for (const route of v1Routes) {
        const result = getAuthRequirements(route);
        // Every V1 route with openapi_auth should parse without error
        expect(result).toHaveProperty('required');
        expect(result).toHaveProperty('schemes');
        expect(Array.isArray(result.schemes)).toBe(true);
      }
    });

    it('V1 routes with openapi_auth=basic,anonymous return normalized schemes', () => {
      const statusRoute = v1Routes.find(r => r.path === '/status');
      expect(statusRoute).toBeDefined();

      const result = getAuthRequirements(statusRoute!);
      expect(result.required).toBe(true);
      expect(result.schemes).toContain('basicauth');
      expect(result.schemes).toContain('noauth');
    });

    it('V1 routes with openapi_auth=basic return only basicauth', () => {
      const authcheckRoute = v1Routes.find(r => r.path === '/authcheck');
      expect(authcheckRoute).toBeDefined();

      const result = getAuthRequirements(authcheckRoute!);
      expect(result.required).toBe(true);
      expect(result.schemes).toEqual(['basicauth']);
    });
  });

  // ─── Colonel routes.txt integration ────────────────────────────────

  describe('Colonel routes.txt integration', () => {
    const colonelRoutesPath = join(
      process.cwd(),
      'apps',
      'api',
      'colonel',
      'routes.txt'
    );

    let colonelRoutes: OttoRoute[];

    beforeEach(() => {
      const parsed = parseRoutesFile(colonelRoutesPath);
      colonelRoutes = parsed.routes;
    });

    it('parses at least one route from colonel routes.txt', () => {
      expect(colonelRoutes.length).toBeGreaterThan(0);
    });

    it('all colonel routes have role=colonel as separate param', () => {
      for (const route of colonelRoutes) {
        expect(route.params.role).toBe('colonel');
      }
    });

    it('all colonel routes use auth=sessionauth', () => {
      for (const route of colonelRoutes) {
        expect(route.params.auth).toBe('sessionauth');
      }
    });

    it('getAuthRequirements extracts role=colonel from colonel routes', () => {
      const infoRoute = colonelRoutes.find(r => r.path === '/info');
      expect(infoRoute).toBeDefined();

      const result = getAuthRequirements(infoRoute!);
      expect(result.required).toBe(true);
      expect(result.schemes).toContain('sessionauth');
      expect(result.role).toBe('colonel');
    });

    it('all colonel routes have scope=internal', () => {
      for (const route of colonelRoutes) {
        expect(route.params.scope).toBe('internal');
      }
    });

    it('getAuthRequirements works for every colonel route', () => {
      for (const route of colonelRoutes) {
        const result = getAuthRequirements(route);
        // Every colonel route should require auth with role=colonel
        expect(result.required).toBe(true);
        expect(result.role).toBe('colonel');
        expect(result.schemes).toContain('sessionauth');
      }
    });
  });
});
