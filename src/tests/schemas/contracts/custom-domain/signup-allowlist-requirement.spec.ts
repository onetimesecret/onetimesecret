// src/tests/schemas/contracts/custom-domain/signup-allowlist-requirement.spec.ts
//
// The signup allowlist requirement, TypeScript half. allowlistRequirementMet
// mirrors SignupConfig.allowlist_requirement_error, which is authoritative.
// Both read tests/fixtures/signup_allowlist_requirement_cases.json (Ruby half:
// spec/unit/onetime/models/custom_domain/signup_allowlist_requirement_spec.rb),
// so a rule changed on one side fails a test instead of letting the form offer
// a save the API refuses, or the reverse.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  allowlistRequirementMet,
  SIGNUP_STRATEGY_METADATA,
  type SignupValidationStrategy,
} from '@/schemas/contracts/custom-domain/signup-config';

interface AllowlistCase {
  id: string;
  strategy: SignupValidationStrategy;
  domains: string[] | null;
  allow_base_domain: boolean;
  base_domain: string | null;
  met: boolean;
}

// Vitest's root is the repo root, as for the other shared fixtures. A wrong
// path throws HERE, naming it, rather than yielding an empty case list.
const FIXTURE_PATH = resolve(process.cwd(), 'tests/fixtures/signup_allowlist_requirement_cases.json');
const CASES = (JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as { cases: AllowlistCase[] }).cases;

/**
 * Cases whose removal OR alteration must turn this suite RED: the two that
 * keep an empty effective list from passing, and the one the feature exists
 * for. Kept identical to the Ruby half's pinned tuples.
 */
const PINNED_CASES: Record<string, [string, string[], boolean, string | null, boolean]> = {
  'base-domain-only': ['domain_allowlist', [], true, 'acme.com', true],
  'flag-without-base-domain': ['domain_allowlist', [], true, null, false],
  'empty-list-flag-off': ['domain_allowlist', [], false, 'acme.com', false],
};

describe('the shared allowlist requirement table', () => {
  it('carries cases with unique ids', () => {
    const ids = CASES.map((c) => c.id);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('still carries the pinned cases, unaltered', () => {
    const byId = new Map(CASES.map((c) => [c.id, c]));

    for (const [id, tuple] of Object.entries(PINNED_CASES)) {
      const kase = byId.get(id);
      expect(kase, `pinned case ${id} is missing from the fixture`).toBeDefined();
      expect(
        [kase?.strategy, kase?.domains, kase?.allow_base_domain, kase?.base_domain, kase?.met],
        `pinned case ${id} was altered`
      ).toEqual(tuple);
    }
  });

  it('covers every strategy', () => {
    expect([...new Set(CASES.map((c) => c.strategy))].sort()).toEqual(
      Object.keys(SIGNUP_STRATEGY_METADATA).sort()
    );
  });
});

describe('allowlistRequirementMet', () => {
  it.each(CASES.map((c) => [c.met ? 'passes' : 'fails', c.id, c] as const))(
    '%s %s',
    (_verb, _id, kase) => {
      // The form passes whether the domain has a base domain to derive (the
      // server's base_domain, present or not) as hasBaseDomain.
      const met = allowlistRequirementMet(
        {
          validation_strategy: kase.strategy,
          allowed_signup_domains: kase.domains ?? undefined,
          allow_base_domain: kase.allow_base_domain,
        },
        kase.base_domain !== null
      );
      expect(met).toBe(kase.met);
    }
  );
});
