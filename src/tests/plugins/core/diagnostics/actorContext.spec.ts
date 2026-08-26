// src/tests/plugins/core/diagnostics/actorContext.spec.ts
//
// Tests for the Sentry user-context boundary.
//
// The invariants under test are privacy invariants, not behaviours:
//   1. Only { id, ip_address: null } ever reaches setUser.
//   2. Anything the strict contract does not recognise CLEARS the context
//      rather than partially applying it (fail-closed).
//   3. Anonymous sessions are never given a fallback id.
//   4. User context is the ONLY dimension written, so setUser(null) is a
//      complete eviction — no tag survives a logout.
//   5. Both scopes always agree.

import { beforeEach, describe, expect, it, vi } from 'vitest';

const { mockGetBootstrapValue } = vi.hoisted(() => ({
  mockGetBootstrapValue: vi.fn(),
}));

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapValue: mockGetBootstrapValue,
}));

import {
  applyActorContext,
  parseDiagnosticsRefBlock,
  resolveDiagnosticsRef,
  sanitizeEventUser,
  type ActorContextScope,
} from '@/plugins/core/diagnostics/actorContext';

// No `setTag` on the mock, deliberately: the actor boundary writes user context
// and nothing else, so a re-introduced tag write would be a TypeError here
// rather than an unasserted extra call.
function createScope() {
  return {
    setUser: vi.fn(),
  } as unknown as ActorContextScope & {
    setUser: ReturnType<typeof vi.fn>;
  };
}

// A ref of the exact shape the server derives: 16 lowercase hex chars
// (Onetime::Utils::DiagnosticsRef::REF_LENGTH). Fixtures MUST use this shape —
// the contract checks content, not just type.
const REF = 'a1b2c3d4e5f60718';
const OTHER_REF = '00112233445566ff';
const VALID = { actor_ref: REF } as const;

describe('parseDiagnosticsRefBlock', () => {
  it('accepts a well-formed single-key block', () => {
    expect(parseDiagnosticsRefBlock(VALID)).toEqual(VALID);
  });

  it('accepts any ref of the derivation shape', () => {
    expect(parseDiagnosticsRefBlock({ actor_ref: OTHER_REF })).toEqual({
      actor_ref: OTHER_REF,
    });
  });

  it('returns null for an absent block (anonymous session)', () => {
    expect(parseDiagnosticsRefBlock(undefined)).toBeNull();
    expect(parseDiagnosticsRefBlock(null)).toBeNull();
  });

  // Fail-closed: this is the case that matters. A server that starts sending an
  // extra field must not have it silently stripped-and-accepted, because a
  // stripped field is one refactor away from being forwarded.
  it('REJECTS a block carrying an extra key (strict, not passthrough)', () => {
    expect(parseDiagnosticsRefBlock({ ...VALID, email: 'user@example.com' })).toBeNull();
  });

  // Contract NARROWING, pinned. `actor_scope` was a real wire field; the
  // deployment/federated axis it named is gone. Because the block is a
  // strictObject, a legacy payload still carrying it is REJECTED outright
  // rather than quietly stripped — a mixed-version deploy runs unidentified
  // instead of half-identified.
  it('REJECTS a legacy block still carrying the retired actor_scope key', () => {
    expect(parseDiagnosticsRefBlock({ actor_ref: REF, actor_scope: 'deployment' })).toBeNull();
    expect(parseDiagnosticsRefBlock({ actor_ref: REF, actor_scope: 'federated' })).toBeNull();
  });

  it('rejects an empty or non-string ref', () => {
    expect(parseDiagnosticsRefBlock({ actor_ref: '' })).toBeNull();
    expect(parseDiagnosticsRefBlock({ actor_ref: 42 })).toBeNull();
  });

  // THE LAUNDERING CASE. A shape-only check (non-empty string) passes this
  // block: the one permitted key, a non-empty string. It would become
  // `user.id = "alice@example.com"` on every error and transaction, with the
  // outbound gate dutifully stripping the `email` KEY it was never in.
  it('REJECTS an email in the ref field — content, not just shape', () => {
    expect(parseDiagnosticsRefBlock({ actor_ref: 'alice@example.com' })).toBeNull();
  });

  it('rejects refs of the wrong width, case, or alphabet', () => {
    expect(parseDiagnosticsRefBlock({ actor_ref: 'ref' })).toBeNull();
    // Too short / too long by one.
    expect(parseDiagnosticsRefBlock({ actor_ref: 'a1b2c3d4e5f6071' })).toBeNull();
    expect(parseDiagnosticsRefBlock({ actor_ref: 'a1b2c3d4e5f607180' })).toBeNull();
    // Uppercase: Ruby's hexdigest is lowercase, so this is not our value.
    expect(parseDiagnosticsRefBlock({ actor_ref: 'A1B2C3D4E5F60718' })).toBeNull();
    // Non-hex, right length.
    expect(parseDiagnosticsRefBlock({ actor_ref: 'zzzzzzzzzzzzzzzz' })).toBeNull();
    // A full-width digest (32 hex) is NOT a diagnostics ref.
    expect(
      parseDiagnosticsRefBlock({
        actor_ref: 'a1b2c3d4e5f60718a1b2c3d4e5f60718',
      })
    ).toBeNull();
    // Whitespace padding must not be tolerated (anchored pattern).
    expect(parseDiagnosticsRefBlock({ actor_ref: ' a1b2c3d4e5f60718' })).toBeNull();
  });

  it('rejects a block missing actor_ref', () => {
    expect(parseDiagnosticsRefBlock({})).toBeNull();
    expect(parseDiagnosticsRefBlock({ actor_ref: undefined })).toBeNull();
  });

  it('rejects non-object shapes', () => {
    expect(parseDiagnosticsRefBlock(REF)).toBeNull();
    expect(parseDiagnosticsRefBlock([REF])).toBeNull();
  });
});

describe('resolveDiagnosticsRef', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('reads the diagnostics_ref key from the pre-Pinia bootstrap snapshot', () => {
    mockGetBootstrapValue.mockReturnValue(VALID);
    expect(resolveDiagnosticsRef()).toEqual(VALID);
    expect(mockGetBootstrapValue).toHaveBeenCalledWith('diagnostics_ref');
  });

  it('returns null when the block is absent', () => {
    mockGetBootstrapValue.mockReturnValue(undefined);
    expect(resolveDiagnosticsRef()).toBeNull();
  });
});

describe('applyActorContext', () => {
  it('sets only { id, ip_address: null } — never email, name, or an IP', () => {
    const scope = createScope();

    applyActorContext([scope], VALID);

    expect(scope.setUser).toHaveBeenCalledTimes(1);
    const user = scope.setUser.mock.calls[0][0];
    // Exact shape, asserted with toStrictEqual so an extra key fails the test.
    expect(user).toStrictEqual({ id: REF, ip_address: null });
    expect(Object.keys(user)).toEqual(['id', 'ip_address']);
  });

  it('does not forward extra fields even if they survive into the block', () => {
    const scope = createScope();

    // Bypasses the parser deliberately: proves applyActorContext constructs
    // the user literally rather than spreading its input.
    applyActorContext([scope], {
      ...VALID,
      email: 'user@example.com',
    } as never);

    expect(scope.setUser.mock.calls[0][0]).toStrictEqual({
      id: REF,
      ip_address: null,
    });
  });

  // A TypeScript type is not a runtime guarantee: a cast, a hand-built object,
  // or a caller that skips parseDiagnosticsRefBlock all reach here. An
  // unrecognised ref must clear the context rather than partially apply it.
  it('refuses an unrecognised ref and clears the user context', () => {
    const scope = createScope();

    applyActorContext([scope], {
      actor_ref: 'alice@example.com',
    } as never);

    expect(scope.setUser).toHaveBeenCalledWith(null);
  });

  it('clears the user context when given null (logout / anonymous)', () => {
    const scope = createScope();

    applyActorContext([scope], null);

    expect(scope.setUser).toHaveBeenCalledWith(null);
  });

  it('never mints a fallback id for an anonymous session', () => {
    const scope = createScope();
    applyActorContext([scope], null);
    expect(scope.setUser).toHaveBeenCalledTimes(1);
    expect(scope.setUser.mock.calls[0][0]).toBeNull();
  });

  it('writes to EVERY scope so isolated and current cannot disagree', () => {
    const isolated = createScope();
    const current = createScope();

    applyActorContext([isolated, current], VALID);

    for (const scope of [isolated, current]) {
      expect(scope.setUser).toHaveBeenCalledWith({
        id: REF,
        ip_address: null,
      });
    }
  });

  it('clears every scope on account change', () => {
    const isolated = createScope();
    const current = createScope();

    applyActorContext([isolated, current], VALID);
    applyActorContext([isolated, current], null);

    expect(isolated.setUser).toHaveBeenLastCalledWith(null);
    expect(current.setUser).toHaveBeenLastCalledWith(null);
  });
});

describe('sanitizeEventUser (outbound final gate)', () => {
  it('strips email, username, name, and any IP from user context', () => {
    const event = {
      user: {
        id: REF,
        email: 'user@example.com',
        username: 'someone',
        name: 'Some One',
        ip_address: '203.0.113.7',
        geo: { country_code: 'CA' },
      },
    };

    sanitizeEventUser(event);

    expect(event.user).toStrictEqual({ id: REF, ip_address: null });
  });

  it('forces ip_address to null even when Sentry asked for auto-inference', () => {
    const event = { user: { id: REF, ip_address: '{{auto}}' } };
    sanitizeEventUser(event);
    expect(event.user).toStrictEqual({ id: REF, ip_address: null });
  });

  // The gate is a FILTER, not a launderer. `Sentry.setUser({ id: cust.email })`
  // is one line away anywhere in the app and never touches actorContext.ts;
  // keeping `id` on a type check alone would forward that address on every
  // event while deleting the `email` key beside it.
  it('DROPS the user context when id is an email rather than an opaque ref', () => {
    const event: { user?: Record<string, unknown> } = {
      user: { id: 'alice@example.com' },
    };
    sanitizeEventUser(event);
    expect(event.user).toBeUndefined();
  });

  it('drops the user context for any id that is not the derivation shape', () => {
    for (const id of [
      'opaque-deterministic-reference',
      'A1B2C3D4E5F60718',
      'a1b2c3d4e5f6071',
      'a1b2c3d4e5f60718a1b2c3d4e5f60718',
      'cust_12345',
      42,
    ]) {
      const event: { user?: Record<string, unknown> } = {
        user: { id } as Record<string, unknown>,
      };
      sanitizeEventUser(event);
      expect(event.user).toBeUndefined();
    }
  });

  it('drops the whole user context when there is no usable opaque id', () => {
    const event: { user?: Record<string, unknown> } = {
      user: { email: 'user@example.com', ip_address: '{{auto}}' },
    };
    sanitizeEventUser(event);
    expect(event.user).toBeUndefined();
  });

  it('drops the user context for an empty-string id', () => {
    const event: { user?: Record<string, unknown> } = { user: { id: '' } };
    sanitizeEventUser(event);
    expect(event.user).toBeUndefined();
  });

  it('leaves events without user context alone', () => {
    const event: { user?: Record<string, unknown> | null } = {};
    sanitizeEventUser(event);
    expect(event.user).toBeUndefined();
  });
});
