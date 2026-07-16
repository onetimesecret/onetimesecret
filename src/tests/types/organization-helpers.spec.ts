// src/tests/types/organization-helpers.spec.ts

/**
 * Unit tests for invitation status display helpers.
 *
 * @see src/types/organization.ts
 * @see src/apps/workspace/account/settings/OrganizationSettings.vue - consumer
 */

import {
  effectiveInvitationStatus,
  invitationStatusLabelKey,
  INVITATION_STATUSES,
  LOCALIZED_INVITATION_STATUSES,
} from '@/types/organization';
import { describe, expect, it } from 'vitest';

// Fixed clock so expiry comparisons are deterministic.
const NOW_MS = 1_700_000_000_000; // ms
const NOW_S = NOW_MS / 1000; // s
const FUTURE_S = NOW_S + 3600; // expires in 1h
const PAST_S = NOW_S - 3600; // expired 1h ago

describe('effectiveInvitationStatus', () => {
  it('keeps a pending invitation pending while it has time left', () => {
    expect(effectiveInvitationStatus('pending', FUTURE_S, NOW_MS)).toBe(INVITATION_STATUSES.PENDING);
  });

  it('surfaces a pending-but-past-expiry invitation as expired', () => {
    expect(effectiveInvitationStatus('pending', PAST_S, NOW_MS)).toBe(INVITATION_STATUSES.EXPIRED);
  });

  it('treats the exact expiry boundary as expired', () => {
    expect(effectiveInvitationStatus('pending', NOW_S, NOW_MS)).toBe(INVITATION_STATUSES.EXPIRED);
  });

  it('never reinterprets a non-pending status, even past expiry', () => {
    // Only pending flips to expired; a terminal status stands as-is.
    expect(effectiveInvitationStatus('accepted', PAST_S, NOW_MS)).toBe(INVITATION_STATUSES.ACCEPTED);
    expect(effectiveInvitationStatus('declined', PAST_S, NOW_MS)).toBe(INVITATION_STATUSES.DECLINED);
  });

  it('passes an already-expired status through unchanged', () => {
    expect(effectiveInvitationStatus('expired', PAST_S, NOW_MS)).toBe(INVITATION_STATUSES.EXPIRED);
  });

  // Guards the whole-second comparison: expiry is floored to seconds to match
  // the row countdown (formatTimeRemaining), so a sub-second-future expiry must
  // still read as pending rather than flipping early on millisecond precision.
  it('stays pending for a sub-second-future expiry within the same second', () => {
    expect(effectiveInvitationStatus('pending', NOW_S + 0.5, NOW_MS + 700)).toBe(
      INVITATION_STATUSES.PENDING
    );
  });

  it('flips to expired once the whole second has ticked past expiry', () => {
    expect(effectiveInvitationStatus('pending', NOW_S + 0.5, NOW_MS + 1000)).toBe(
      INVITATION_STATUSES.EXPIRED
    );
  });
});

describe('invitationStatusLabelKey', () => {
  it('maps every localized status to its label key', () => {
    for (const status of LOCALIZED_INVITATION_STATUSES) {
      expect(invitationStatusLabelKey(status)).toBe(`web.organizations.invitations.status.${status}`);
    }
  });

  it('covers the four contract statuses plus revoked', () => {
    expect(invitationStatusLabelKey('pending')).toBe('web.organizations.invitations.status.pending');
    expect(invitationStatusLabelKey('accepted')).toBe('web.organizations.invitations.status.accepted');
    expect(invitationStatusLabelKey('declined')).toBe('web.organizations.invitations.status.declined');
    expect(invitationStatusLabelKey('expired')).toBe('web.organizations.invitations.status.expired');
    expect(invitationStatusLabelKey('revoked')).toBe('web.organizations.invitations.status.revoked');
  });

  it('returns null for an unknown/future status (fallback path)', () => {
    // 'active' is the raw backend enum; the invitation contract exposes it as
    // 'accepted', so 'active' has no label and must fall back to the raw value.
    expect(invitationStatusLabelKey('active')).toBeNull();
    expect(invitationStatusLabelKey('some_future_status')).toBeNull();
    expect(invitationStatusLabelKey('')).toBeNull();
  });
});

describe('status label resolution (mapping + fallback, as the UI composes them)', () => {
  const resolve = (status: string, expiresAtSeconds: number): string => {
    const effective = effectiveInvitationStatus(status, expiresAtSeconds, NOW_MS);
    return invitationStatusLabelKey(effective) ?? effective;
  };

  it('resolves a live pending invitation to the pending label key', () => {
    expect(resolve('pending', FUTURE_S)).toBe('web.organizations.invitations.status.pending');
  });

  it('resolves a lapsed pending invitation to the expired label key', () => {
    expect(resolve('pending', PAST_S)).toBe('web.organizations.invitations.status.expired');
  });

  it('falls back to the raw status string when there is no label', () => {
    expect(resolve('active', FUTURE_S)).toBe('active');
  });
});
