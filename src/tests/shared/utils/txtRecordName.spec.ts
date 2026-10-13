// src/tests/shared/utils/txtRecordName.spec.ts

import { txtChallengeLabel, txtRecordName } from '@/shared/utils/txtRecordName';
import { describe, expect, it } from 'vitest';

const CHALLENGE = '_onetime-challenge-abc1234';

describe('txtChallengeLabel', () => {
  it.each([
    ['ASCII subdomain', `${CHALLENGE}.secrets`],
    ['A-label subdomain', `${CHALLENGE}.xn--bcher-kva`],
    ['Unicode subdomain (earlier versions)', `${CHALLENGE}.bücher`],
    ['multi-label subdomain', `${CHALLENGE}.a.b`],
    ['apex (no subdomain)', CHALLENGE],
  ])('%s: the first label', (_label, host) => {
    expect(txtChallengeLabel(host)).toBe(CHALLENGE);
  });

  it('is empty for a missing host', () => {
    expect(txtChallengeLabel(undefined)).toBe('');
    expect(txtChallengeLabel(null)).toBe('');
    expect(txtChallengeLabel('')).toBe('');
  });
});

describe('txtRecordName', () => {
  it('Unicode subdomain: the A-label host, the zone, and the display spelling', () => {
    expect(
      txtRecordName({
        base_domain: 'example.com',
        txt_validation_host: `${CHALLENGE}.xn--bcher-kva`,
        txt_validation_record: `${CHALLENGE}.xn--bcher-kva.example.com`,
        txt_validation_record_display: `${CHALLENGE}.bücher.example.com`,
      })
    ).toEqual({
      host: `${CHALLENGE}.xn--bcher-kva`,
      zone: '.example.com',
      displayName: `${CHALLENGE}.bücher.example.com`,
    });
  });

  it('Unicode registrable domain: the zone in A-label form, not as typed', () => {
    expect(
      txtRecordName({
        base_domain: 'bücher.de',
        txt_validation_host: CHALLENGE,
        txt_validation_record: `${CHALLENGE}.xn--bcher-kva.de`,
        txt_validation_record_display: `${CHALLENGE}.bücher.de`,
      })
    ).toEqual({
      host: CHALLENGE,
      zone: '.xn--bcher-kva.de',
      displayName: `${CHALLENGE}.bücher.de`,
    });
  });

  it('host stored with a Unicode subdomain by an earlier version: the A-label host', () => {
    expect(
      txtRecordName({
        base_domain: 'example.com',
        txt_validation_host: `${CHALLENGE}.bücher`,
        txt_validation_record: `${CHALLENGE}.xn--bcher-kva.example.com`,
        txt_validation_record_display: `${CHALLENGE}.bücher.example.com`,
      })
    ).toEqual({
      host: `${CHALLENGE}.xn--bcher-kva`,
      zone: '.example.com',
      displayName: `${CHALLENGE}.bücher.example.com`,
    });
  });

  it('ASCII name: no display hint, same host and zone as before', () => {
    expect(
      txtRecordName({
        base_domain: 'example.com',
        txt_validation_host: `${CHALLENGE}.secrets`,
        txt_validation_record: `${CHALLENGE}.secrets.example.com`,
        txt_validation_record_display: `${CHALLENGE}.secrets.example.com`,
      })
    ).toEqual({ host: `${CHALLENGE}.secrets`, zone: '.example.com', displayName: null });
  });

  it('a display spelling that differs only in case is not a different name', () => {
    expect(
      txtRecordName({
        base_domain: 'example.com',
        txt_validation_host: `${CHALLENGE}.secrets`,
        txt_validation_record: `${CHALLENGE}.secrets.example.com`,
        txt_validation_record_display: `${CHALLENGE}.Secrets.Example.com`,
      }).displayName
    ).toBeNull();
  });

  it('apex domain: the challenge label alone, then the zone', () => {
    expect(
      txtRecordName({
        base_domain: 'example.com',
        txt_validation_host: CHALLENGE,
        txt_validation_record: `${CHALLENGE}.example.com`,
        txt_validation_record_display: `${CHALLENGE}.example.com`,
      })
    ).toEqual({ host: CHALLENGE, zone: '.example.com', displayName: null });
  });

  it('multi-label subdomain: every subdomain label stays in the host', () => {
    expect(
      txtRecordName({
        base_domain: 'example.co.uk',
        txt_validation_host: `${CHALLENGE}.a.b`,
        txt_validation_record: `${CHALLENGE}.a.b.example.co.uk`,
      })
    ).toEqual({ host: `${CHALLENGE}.a.b`, zone: '.example.co.uk', displayName: null });
  });

  describe('when the A-label name does not split against the stored host and base domain', () => {
    // Label separators other than "." (U+3002) are mapped to "." on conversion,
    // so the A-label name has more labels than the stored spelling.
    it('label counts differ: the full A-label name as the host, no zone', () => {
      expect(
        txtRecordName({
          base_domain: 'example。com',
          txt_validation_host: CHALLENGE,
          txt_validation_record: `${CHALLENGE}.example.com`,
        })
      ).toEqual({ host: `${CHALLENGE}.example.com`, zone: undefined, displayName: null });
    });

    it('challenge labels differ: the full A-label name as the host, no zone', () => {
      expect(
        txtRecordName({
          base_domain: 'example.com',
          txt_validation_host: '_onetime-challenge-0000000.secrets',
          txt_validation_record: `${CHALLENGE}.secrets.example.com`,
        })
      ).toEqual({ host: `${CHALLENGE}.secrets.example.com`, zone: undefined, displayName: null });
    });

    it('no stored host: the full A-label name as the host, no zone', () => {
      expect(
        txtRecordName({
          base_domain: 'example.com',
          txt_validation_host: null,
          txt_validation_record: `${CHALLENGE}.example.com`,
        }).host
      ).toBe(`${CHALLENGE}.example.com`);
    });
  });

  describe('without txt_validation_record (no challenge yet, or no A-label form)', () => {
    it('falls back to the stored host and base domain', () => {
      expect(
        txtRecordName({
          base_domain: 'example.com',
          txt_validation_host: `${CHALLENGE}.secrets`,
          txt_validation_record: null,
          txt_validation_record_display: `${CHALLENGE}.secrets.example.com`,
        })
      ).toEqual({ host: `${CHALLENGE}.secrets`, zone: '.example.com', displayName: null });
    });

    it('older payload without the field: the stored host and base domain', () => {
      expect(
        txtRecordName({ base_domain: 'example.com', txt_validation_host: `${CHALLENGE}.secrets` })
      ).toEqual({ host: `${CHALLENGE}.secrets`, zone: '.example.com', displayName: null });
    });

    it('no base domain: no zone', () => {
      expect(txtRecordName({ txt_validation_host: CHALLENGE })).toEqual({
        host: CHALLENGE,
        zone: undefined,
        displayName: null,
      });
    });

    it('no record at all: empty host', () => {
      expect(txtRecordName(undefined)).toEqual({ host: '', zone: undefined, displayName: null });
    });
  });
});
