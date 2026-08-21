// src/tests/plugins/core/scrubSensitiveStrings.spec.ts
//
// Unit tests for scrubSensitiveStrings function.
// Tests scrubbing of emails, verifiable IDs, and sensitive paths from arbitrary text.

import { describe, expect, it } from 'vitest';
import { scrubSensitiveStrings } from '@/plugins/core/enableDiagnostics';

describe('scrubSensitiveStrings', () => {
  it('scrubs email addresses from text', () => {
    const text = 'Contact user@example.com for support';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Contact [EMAIL_REDACTED] for support');
  });

  it('scrubs multiple email addresses', () => {
    const text = 'From: alice@example.com To: bob@example.com';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('From: [EMAIL_REDACTED] To: [EMAIL_REDACTED]');
  });

  it('scrubs 62-char verifiable IDs', () => {
    const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
    const text = `Processing secret ${id62}`;
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Processing secret [REDACTED]');
  });

  it('scrubs sensitive path patterns in text', () => {
    const text = 'Error loading /secret/abc123def';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Error loading /secret/[REDACTED]');
  });

  it('scrubs /private/ paths in text', () => {
    const text = 'Failed to fetch /private/xyz789';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Failed to fetch /private/[REDACTED]');
  });

  it('scrubs /receipt/ paths in text', () => {
    const text = 'Receipt at /receipt/receipt123';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Receipt at /receipt/[REDACTED]');
  });

  it('scrubs /incoming/ paths in text', () => {
    const text = 'Incoming at /incoming/incoming456';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Incoming at /incoming/[REDACTED]');
  });

  it('scrubs multiple sensitive patterns in one string', () => {
    const text = 'User user@example.com accessed /secret/abc123';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('User [EMAIL_REDACTED] accessed /secret/[REDACTED]');
  });

  it('handles empty string input', () => {
    expect(scrubSensitiveStrings('')).toBe('');
  });

  it('handles null input gracefully', () => {
    expect(scrubSensitiveStrings(null as unknown as string)).toBe(null);
  });

  it('handles undefined input gracefully', () => {
    expect(scrubSensitiveStrings(undefined as unknown as string)).toBe(undefined);
  });

  it('leaves text without sensitive data unchanged', () => {
    const text = 'Application started successfully';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Application started successfully');
  });
});

// ───────────────────────────────────────────────────────────────────────────
// OPAQUE-IDENTIFIER NETS
//
// The projection routes every emitted field path through this function, so its
// coverage is load-bearing for payload-derived record keys — and its
// FALSE-POSITIVE behaviour is load-bearing for every stack frame, version
// string and schema field name that also passes through. Both directions are
// asserted; a net that eats ordinary words would degrade every event on the
// platform, which is a worse outcome than the leak it prevents.
// ───────────────────────────────────────────────────────────────────────────

describe('scrubSensitiveStrings — opaque identifier nets', () => {
  it('redacts a prefixed opaque id inside a resolved API path', () => {
    // The exact string that reached telemetry verbatim before this net existed.
    const result = scrubSensitiveStrings('/api/colonel/organizations/org_9f3a2b1c8d7e6f50');
    expect(result).toBe('/api/colonel/organizations/[ID_REDACTED]');
  });

  it('redacts Stripe-shaped object ids', () => {
    expect(scrubSensitiveStrings('customer cus_NffrFeUfNV2Hib')).toBe(
      'customer [ID_REDACTED]'
    );
    expect(scrubSensitiveStrings('sub_1PxyZa2eZvKYlo2C')).toBe('[ID_REDACTED]');
  });

  it('redacts credential-prefixed keys whole, underscores included', () => {
    const result = scrubSensitiveStrings('params: { leaked: "sk_live_SUPER_SECRET" }');
    expect(result).toBe('params: { leaked: "[SECRET_REDACTED]" }');
    expect(result).not.toContain('SUPER_SECRET');
    expect(scrubSensitiveStrings('whsec_A1b2C3d4E5f6')).toBe('[SECRET_REDACTED]');
  });

  it('redacts a bare hyphenated UUID', () => {
    expect(scrubSensitiveStrings('id 3f2504e0-4f89-11d3-9a0c-0305e82c3301 failed')).toBe(
      'id [UUID_REDACTED] failed'
    );
  });

  it('redacts Onetime Secret external identifiers (prefix + 25 base36)', () => {
    // `feature :external_identifier, format: 'on%<id>s'` over a 25-char base36
    // encoding of 128 bits.
    expect(scrubSensitiveStrings('org on3k9x7q2m4v8b1n5c0z6t2wy73')).toBe('org [EXTID_REDACTED]');
  });

  it('redacts IPv4 literals in a resolved admin path', () => {
    // /api/colonel/banned-ips/:ip is a real request (AdminBannedIps.vue).
    expect(scrubSensitiveStrings('/api/colonel/banned-ips/203.0.113.5')).toBe(
      '/api/colonel/banned-ips/[IP_REDACTED]'
    );
  });

  it('redacts IPv6 literals', () => {
    expect(scrubSensitiveStrings('from 2001:db8::42 refused')).toBe('from [IP_REDACTED] refused');
    expect(scrubSensitiveStrings('fe80:0000:0000:0000:0202:b3ff:fe1e:8329')).toBe(
      '[IP_REDACTED]'
    );
  });

  it('gives each net its own sentinel so the reader knows WHAT was removed', () => {
    const result = scrubSensitiveStrings(
      'user@example.com org_9f3a2b1c8d7e6f50 sk_live_ABCDEF 203.0.113.5'
    );
    expect(result).toBe('[EMAIL_REDACTED] [ID_REDACTED] [SECRET_REDACTED] [IP_REDACTED]');
  });

  // ── Negative cases: over-scrubbing is a regression, not a win ─────────────

  it.each([
    // The schema field whose Integer-vs-string drift this whole branch exists
    // to diagnose. If this is ever redacted, the telemetry stops being useful.
    'record.subscription_period_end',
    // Real schema field names in this tree that a naive `[a-z]{2,8}_\w{6,}`
    // net eats: colonel-sessions.ts, billing.ts, colonel.ts.
    'org_context',
    'price_formatted',
    'price_nickname',
    'price_metadata',
    'mem_fragmentation_ratio',
    'sub_total',
    'stripe_customer_id',
    // Ordinary route words and paths.
    '/api/v2/status',
    '/api/colonel/organizations/:org_id',
    // Version and build strings.
    'v1.2.3-rc.4',
    '10.0.19041.1',
    'ruby 3.4.10 (2026-01-15 revision abc1234) [arm64-darwin27]',
    // Hex-looking English and ops tokens.
    'decade faced a beefed cafe',
    'commit 9ebdbd0374a1f2c3d4e5f60718293a4b5c6d7e8f',
    // A Sentry trace_id is 32 bare hex — deliberately NOT matched by the UUID
    // net, because it is how a frontend event joins its backend transaction.
    'trace_id=4bf92f3577b34da6a3ce929d0e0e4736',
    // Ruby scope operators, which the IPv6 net must not read as an address.
    'Onetime::Utils::TelemetryRef#keying',
    'at Foo::Bar#baz (/app/lib/onetime/logic/base.rb:107)',
    // Clock times: colons, digits, no doubled colon.
    '2026-07-30T12:34:56.789Z',
    // Loopback is a machine role, not a person, and is worth keeping readable.
    'redis://127.0.0.1:6379/0',
  ])('leaves ops-useful text intact: %s', (text) => {
    expect(scrubSensitiveStrings(text)).toBe(text);
  });
});
