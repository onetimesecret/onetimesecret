// src/tests/utils/telemetry/collectionChildLiterals.spec.ts
//
// THE REGENERATION STORY for `COLLECTION_CHILD_LITERALS`.
//
// That set is the ONLY escape from the positional rule in `apiRouteContext`:
// a static word listed there survives verbatim under a mapped collection
// parent, and anything else becomes the collection's parameter name. It is
// therefore derived from the Ruby route table, not chosen — and a hand-kept
// closed list with no regeneration story drifts, which is exactly what happened:
// `status` and `validate` were missing while `sso` was present with a cited
// route that does not exist, so three live endpoints collapsed into a param:
//
//     /api/v2/secret/status  -> /api/v2/secret/:key
//     /api/v3/secret/status  -> /api/v3/secret/:key
//     /api/incoming/validate -> /api/incoming/:key
//
// This file re-derives the set from `apps/api/*/routes.txt` on every run, so
// the next route change breaks a test instead of silently merging two
// endpoints' issues in Sentry. The failure message names the correct set.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  COLLECTION_CHILD_LITERALS,
  PARAM_NAME_BY_COLLECTION,
  parameterizeApiPath,
} from '@/utils/telemetry/apiRouteContext';

/**
 * Mount prefix per API app, mirroring `@uri_prefix` in
 * `apps/api/<app>/application.rb`. Kept here rather than parsed so a typo in
 * this map is visible; the assertion below re-reads the .rb files to prove
 * these are still the real prefixes.
 */
const URI_PREFIX: Readonly<Record<string, string>> = {
  account: '/api/account',
  colonel: '/api/colonel',
  domains: '/api/domains',
  incoming: '/api/incoming',
  invite: '/api/invite',
  organizations: '/api/organizations',
  v1: '/api/v1',
  v2: '/api/v2',
  v3: '/api/v3',
};

const ROUTE_LINE = /^(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\s+(\S+)/;

/** A segment the route table itself declares as a parameter. */
const DECLARED_PARAM = /^[:{$]/;

function readRepoFile(relativePath: string): string {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8');
}

/** Every mounted route path in the Ruby route table, prefix included. */
function allRoutePaths(): string[] {
  const paths: string[] = [];
  for (const [app, prefix] of Object.entries(URI_PREFIX)) {
    for (const raw of readRepoFile(`apps/api/${app}/routes.txt`).split('\n')) {
      const line = raw.trim();
      if (line.length === 0 || line.startsWith('#')) continue;
      const match = ROUTE_LINE.exec(line);
      if (!match) continue;
      const path = match[2] === '/' ? '' : match[2];
      paths.push(`${prefix}${path}`);
    }
  }
  return paths;
}

/**
 * The set the module SHOULD hold: every static segment sitting directly under a
 * `PARAM_NAME_BY_COLLECTION` key anywhere in the route table.
 */
function deriveCollectionChildLiterals(): { literals: string[]; evidence: Map<string, string[]> } {
  const evidence = new Map<string, string[]>();
  for (const path of allRoutePaths()) {
    const segments = path.split('/');
    for (let i = 1; i < segments.length; i += 1) {
      const parent = segments[i - 1];
      const segment = segments[i];
      if (!(parent in PARAM_NAME_BY_COLLECTION)) continue;
      if (segment.length === 0 || DECLARED_PARAM.test(segment)) continue;
      const routes = evidence.get(segment) ?? [];
      if (!routes.includes(path)) routes.push(path);
      evidence.set(segment, routes);
    }
  }
  return { literals: [...evidence.keys()].sort(), evidence };
}

describe('COLLECTION_CHILD_LITERALS is derived from the route table', () => {
  it('the uri_prefix map still matches apps/api/*/application.rb', () => {
    for (const [app, prefix] of Object.entries(URI_PREFIX)) {
      expect(readRepoFile(`apps/api/${app}/application.rb`)).toContain(`@uri_prefix = '${prefix}'`);
    }
  });

  it('the route table parses into a non-trivial number of routes', () => {
    // A guard on the guard: a parser that silently matched nothing would make
    // every assertion below vacuously pass.
    expect(allRoutePaths().length).toBeGreaterThan(150);
  });

  it('holds exactly the static children of a mapped collection, no more, no less', () => {
    const { literals } = deriveCollectionChildLiterals();

    expect([...COLLECTION_CHILD_LITERALS].sort()).toEqual(literals);
  });

  it('every entry cites at least one route that exists', () => {
    const { evidence } = deriveCollectionChildLiterals();

    for (const literal of COLLECTION_CHILD_LITERALS) {
      expect(evidence.get(literal) ?? []).not.toEqual([]);
    }
  });

  it('sso is NOT a child of any mapped collection (its cited route never existed)', () => {
    // Every `sso` route hangs off a resolved id, so its parent is the extid and
    // never `domains`. The old justification cited `/api/incoming/sso/mailer`;
    // apps/api/incoming/routes.txt declares only /config, /secret, /validate.
    const { evidence } = deriveCollectionChildLiterals();

    expect(evidence.has('sso')).toBe(false);
    expect(COLLECTION_CHILD_LITERALS.has('sso')).toBe(false);
    expect(readRepoFile('apps/api/incoming/routes.txt')).not.toContain('/sso');
    expect(parameterizeApiPath('/api/domains/dom4bcdefghijk/sso')).toBe(
      '/api/domains/:domain_id/sso'
    );
  });

  it('the three regressed endpoints keep their own identity', () => {
    expect(parameterizeApiPath('/api/v2/secret/status')).toBe('/api/v2/secret/status');
    expect(parameterizeApiPath('/api/v3/secret/status')).toBe('/api/v3/secret/status');
    expect(parameterizeApiPath('/api/incoming/validate')).toBe('/api/incoming/validate');
  });

  it('every real route in the table survives parameterization unchanged except at its params', () => {
    // The positional and shape rules may only rewrite segments the route table
    // itself declares as parameters. A literal route word being rewritten is
    // the over-parameterization the heuristic's docblock claims does not occur;
    // this is that claim, executed over all of apps/api.
    const rewrittenLiterals: string[] = [];

    for (const path of allRoutePaths()) {
      const before = path.split('/');
      const after = (parameterizeApiPath(path) ?? '').split('/');
      for (let i = 0; i < before.length; i += 1) {
        if (before[i] === after[i]) continue;
        if (DECLARED_PARAM.test(before[i])) continue;
        rewrittenLiterals.push(`${path}: ${before[i]} -> ${after[i]}`);
      }
    }

    expect(rewrittenLiterals).toEqual([]);
  });
});

describe('the positional rule never invents an identifier from an empty segment', () => {
  it('a trailing slash does not manufacture a phantom id', () => {
    // Regression: `/api/organizations/` reported as `/api/organizations/:org_id`,
    // merging a LIST endpoint's failures into its DETAIL endpoint's issue —
    // precisely the Colonel org flow this branch exists for.
    expect(parameterizeApiPath('/api/organizations/')).toBe('/api/organizations/');
    expect(parameterizeApiPath('/api/domains/')).toBe('/api/domains/');
    expect(parameterizeApiPath('/api/v3/secret/')).toBe('/api/v3/secret/');
  });

  it('a doubled slash mid-path does not manufacture one either', () => {
    expect(parameterizeApiPath('/api/organizations//members')).toBe('/api/organizations//members');
  });

  it('the list and detail routes still resolve to DIFFERENT routes', () => {
    expect(parameterizeApiPath('/api/organizations/')).not.toBe(
      parameterizeApiPath('/api/organizations/org_9f3a2b1c8d7e6f50')
    );
  });

  it('a real identifier is still parameterized', () => {
    expect(parameterizeApiPath('/api/organizations/org_9f3a2b1c8d7e6f50')).toBe(
      '/api/organizations/:org_id'
    );
    // The positional guarantee: a short, shapeless id is still caught.
    expect(parameterizeApiPath('/api/colonel/users/alice/diagnostics')).toBe(
      '/api/colonel/users/:user_id/diagnostics'
    );
  });
});
