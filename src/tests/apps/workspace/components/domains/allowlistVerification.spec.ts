// src/tests/apps/workspace/components/domains/allowlistVerification.spec.ts
//
// Verified state of a tenant SSO allowlist entry (#4734): a saved entry
// takes the API's verdict; an unsaved one is judged client-side by A-label
// on a label boundary against the proven set.

import { describe, expect, it } from 'vitest';
import {
  allowlistEntryState,
  toALabel,
  withinVerifiedDomains,
} from '../../../../../apps/workspace/components/domains/allowlistVerification';

describe('toALabel', () => {
  it('lowercases and converts a Unicode name to its A-label', () => {
    expect(toALabel('Bücher.Example')).toBe('xn--bcher-kva.example');
  });

  it('keeps an A-label and strips a trailing dot', () => {
    expect(toALabel('xn--bcher-kva.example.')).toBe('xn--bcher-kva.example');
  });

  it('returns null for an empty name or one the parser rejects', () => {
    expect(toALabel('')).toBeNull();
    expect(toALabel('   ')).toBeNull();
    expect(toALabel('a b.example')).toBeNull();
    expect(toALabel('user@acme.example')).toBeNull();
    expect(toALabel('acme.example/path')).toBeNull();
  });
});

describe('withinVerifiedDomains', () => {
  const proven = ['secrets.acme.example', 'xn--bcher-kva.example'];

  it('accepts the proven name itself and names below it', () => {
    expect(withinVerifiedDomains('secrets.acme.example', proven)).toBe(true);
    expect(withinVerifiedDomains('team.secrets.acme.example', proven)).toBe(true);
  });

  it('refuses the name above and a suffix that is not a label boundary', () => {
    expect(withinVerifiedDomains('acme.example', proven)).toBe(false);
    expect(withinVerifiedDomains('notsecrets.acme.example', proven)).toBe(false);
  });

  it('compares the Unicode and A-label spellings as one name', () => {
    expect(withinVerifiedDomains('bücher.example', proven)).toBe(true);
    expect(withinVerifiedDomains('shop.BÜCHER.example', proven)).toBe(true);
  });

  it('returns null for a name it cannot convert, false against an empty set', () => {
    expect(withinVerifiedDomains('a b.example', proven)).toBeNull();
    expect(withinVerifiedDomains('secrets.acme.example', [])).toBe(false);
  });
});

describe('allowlistEntryState', () => {
  const context = {
    savedAllowedDomains: ['saved-ok.example', 'saved-bad.example'],
    unverifiedAllowedDomains: ['saved-bad.example'],
    verifiedEmailDomains: ['saved-ok.example', 'secrets.acme.example'],
  };

  it('takes the API verdict for a saved entry', () => {
    expect(allowlistEntryState('saved-ok.example', context)).toBe('verified');
    expect(allowlistEntryState('saved-bad.example', context)).toBe('unverified');
  });

  it('judges an unsaved entry against the proven set', () => {
    expect(allowlistEntryState('team.secrets.acme.example', context)).toBe('verified');
    expect(allowlistEntryState('acme.example', context)).toBe('unverified');
  });

  it('is unknown for a saved entry when the API served no proof at all', () => {
    // The serializer's rescue path serves both arrays empty; a saved entry
    // then has no verdict rather than a verified one.
    const noProof = {
      savedAllowedDomains: ['saved.example'],
      unverifiedAllowedDomains: [],
      verifiedEmailDomains: [],
    };
    expect(allowlistEntryState('saved.example', noProof)).toBe('unknown');
  });

  it('is unknown for an unsaved entry it cannot convert', () => {
    expect(allowlistEntryState('a b.example', context)).toBe('unknown');
  });
});
