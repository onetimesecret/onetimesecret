// src/tests/apps/admin/utils/confirmHeader.spec.ts

import { describe, expect, it } from 'vitest';

import {
  accountConfirmToken,
  CONFIRM_HEADER,
  confirmHeaders,
  orgConfirmToken,
} from '@/apps/admin/utils/confirmHeader';

/**
 * The client half of the #4326 confirmation transport.
 *
 * Two properties matter and neither is obvious from reading the four-line
 * module: the value is percent-encoded (HTTP header values are ISO-8859-1 by
 * RFC 7230, and org display names are not), and the two token helpers must
 * agree byte-for-byte with the server's `account_confirm_token` /
 * `org_confirm_token`. A disagreement is a 403 on every gated call.
 */
describe('confirmHeaders', () => {
  it('names the header the server reads', () => {
    expect(CONFIRM_HEADER).toBe('X-OTS-Confirm');
    expect(confirmHeaders('x')).toEqual({ 'X-OTS-Confirm': 'x' });
  });

  it('percent-encodes so a non-ASCII token survives the header charset', () => {
    const token = 'Acme GmbH Überwachung';
    const encoded = confirmHeaders(token)[CONFIRM_HEADER];

    expect(encoded).toBe('Acme%20GmbH%20%C3%9Cberwachung');
    // Round-trips through what Rack::Utils.unescape does server-side.
    expect(decodeURIComponent(encoded)).toBe(token);
  });

  it('encodes an email address, so it never rides a URL unescaped by accident', () => {
    expect(confirmHeaders('victim@example.com')[CONFIRM_HEADER]).toBe('victim%40example.com');
  });

  it('leaves a plain ASCII token intact, so curl works as typed', () => {
    expect(confirmHeaders('sec12345')[CONFIRM_HEADER]).toBe('sec12345');
  });

  it('encodes the colon in a composed token rather than splitting it', () => {
    expect(confirmHeaders('example.com:signin')[CONFIRM_HEADER]).toBe('example.com%3Asignin');
    expect(decodeURIComponent('example.com%3Asignin')).toBe('example.com:signin');
  });
});

describe('accountConfirmToken', () => {
  it('prefers the email', () => {
    expect(accountConfirmToken({ email: 'a@b.example', extid: 'ur_x' })).toBe('a@b.example');
  });

  it('falls back to the public id when the account has no email', () => {
    expect(accountConfirmToken({ email: '   ', extid: 'ur_x' })).toBe('ur_x');
    expect(accountConfirmToken({ email: null, extid: 'ur_x' })).toBe('ur_x');
  });

  it('trims, so a stray space cannot desync the two halves of the gate', () => {
    expect(accountConfirmToken({ email: '  a@b.example  ' })).toBe('a@b.example');
  });

  // Undefined is the fail-closed signal: callers refuse to open the dialog
  // rather than sending a blank token (which the server answers with a 500).
  it('is undefined when there is nothing to name', () => {
    expect(accountConfirmToken(null)).toBeUndefined();
    expect(accountConfirmToken(undefined)).toBeUndefined();
    expect(accountConfirmToken({ email: '', extid: '' })).toBeUndefined();
  });
});

describe('orgConfirmToken', () => {
  it('prefers the display name and falls back to the public id', () => {
    expect(orgConfirmToken({ display_name: 'Acme', extid: 'on_x' })).toBe('Acme');
    expect(orgConfirmToken({ display_name: null, extid: 'on_x' })).toBe('on_x');
    expect(orgConfirmToken(null)).toBeUndefined();
  });
});
