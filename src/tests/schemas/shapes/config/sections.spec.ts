// src/tests/schemas/shapes/config/sections.spec.ts
//
// Spot-checks for the section shapes that restore defaults the contract
// strip removed. The goal isn't field-by-field coverage of every section
// (the JSON Schema generator round-trip in
// `tests/schemas/generation/schema-generation.spec.ts` exercises the
// composed shapes end-to-end) — it's to catch regressions in the most
// load-bearing defaults so a partial config still validates.

import { describe, it, expect } from 'vitest';

import {
  developmentSchema,
  diagnosticsSchema,
  i18nSchema,
  jurisdictionSchema,
  jobsSchema,
  redisSchema,
  emailerSchema,
  featuresIncomingSchema,
  featuresDomainsAcmeSchema,
  siteSchema,
  passphraseSchema,
} from '@/schemas/contracts/config';

import {
  developmentShape,
  diagnosticsShape,
  i18nShape,
  jurisdictionShape,
  jobsShape,
  redisShape,
  redisDbsShape,
  emailerShape,
  featuresIncomingShape,
  featuresDomainsAcmeShape,
  siteShape,
  passphraseShape,
} from '@/schemas/shapes/config';

import { authConfigShape } from '@/schemas/shapes/config/auth';
import { loggingConfigShape } from '@/schemas/shapes/config/logging';

describe('contract vs shape: defaults are absent on contracts, applied on shapes', () => {
  it('development', () => {
    const c = developmentSchema.parse({});
    expect(c.enabled).toBeUndefined();
    expect(c.frontend_host).toBeUndefined();

    const s = developmentShape.parse({});
    expect(s.enabled).toBe(false);
    expect(s.debug).toBe(false);
    expect(s.frontend_host).toBe('http://localhost:5173');
    expect(s.domain_context_enabled).toBe(false);
    expect(s.allow_nil_global_secret).toBe(false);
  });

  it('diagnostics', () => {
    const c = diagnosticsSchema.parse({});
    expect(c.enabled).toBeUndefined();

    const s = diagnosticsShape.parse({});
    expect(s.enabled).toBe(false);
  });

  it('i18n', () => {
    const c = i18nSchema.parse({ fallback_locale: { en: ['en'] } });
    expect(c.default_locale).toBeUndefined();
    expect(c.locales).toBeUndefined();

    const s = i18nShape.parse({ fallback_locale: { en: ['en'] } });
    expect(s.enabled).toBe(false);
    expect(s.default_locale).toBe('en');
    expect(s.locales).toEqual([]);
    expect(s.date_format).toBe('locale');
  });

  it('jurisdiction', () => {
    const minimal = {
      identifier: 'eu',
      display_name_i18n_key: 'web.regions.eu',
      domain: 'eu.example.com',
    };
    const c = jurisdictionSchema.parse(minimal);
    expect(c.enabled).toBeUndefined();

    const s = jurisdictionShape.parse(minimal);
    expect(s.enabled).toBe(true);
  });

  it('jobs', () => {
    const c = jobsSchema.parse({});
    expect(c.enabled).toBeUndefined();
    expect(c.rabbitmq_url).toBeUndefined();

    const s = jobsShape.parse({});
    expect(s.enabled).toBe(false);
    expect(s.rabbitmq_url).toBe('amqp://guest:guest@localhost:5672/dev');
    expect(s.channel_pool_size).toBe(5);
    expect(s.fallback_to_sync).toBe(true);

    // Nested job blocks: contract leaves the toggle undefined, the shape
    // defaults it (only when the block is present — like domain_refresh).
    expect(jobsSchema.parse({ dlq_consumer: {} }).dlq_consumer?.enabled).toBeUndefined();
    expect(jobsShape.parse({ dlq_consumer: {} }).dlq_consumer?.enabled).toBe(true);
  });

  it('redis (storage)', () => {
    const c = redisSchema.parse({});
    expect(c.uri).toBeUndefined();

    const s = redisShape.parse({});
    expect(s.uri).toBe('redis://127.0.0.1:6379');

    const dbs = redisDbsShape.parse({});
    expect(dbs.session).toBe(0);
    expect(dbs.customer).toBe(0);
  });

  it('emailer (mail)', () => {
    const c = emailerSchema.parse({});
    expect(c.mode).toBeUndefined();
    expect(c.port).toBeUndefined();

    const s = emailerShape.parse({});
    expect(s.mode).toBe('smtp');
    expect(s.host).toBe('smtp.provider.com');
    expect(s.port).toBe(587);
    expect(s.from).toBe('CHANGEME@example.com');
    expect(s.from_name).toBe('Support');
  });

  it('features.incoming', () => {
    const c = featuresIncomingSchema.parse({});
    expect(c.enabled).toBeUndefined();
    expect(c.default_ttl).toBeUndefined();

    const s = featuresIncomingShape.parse({});
    expect(s.enabled).toBe(false);
    expect(s.memo_max_length).toBe(50);
    expect(s.default_ttl).toBe(604800);
  });

  it('features.domains.acme', () => {
    const c = featuresDomainsAcmeSchema.parse({});
    expect(c.enabled).toBeUndefined();
    expect(c.listen_address).toBeUndefined();
    expect(c.port).toBeUndefined();

    const s = featuresDomainsAcmeShape.parse({});
    expect(s.enabled).toBe(false);
    expect(s.listen_address).toBe('127.0.0.1');
    expect(s.port).toBe('12020');
  });

  it('site', () => {
    const c = siteSchema.parse({});
    expect(c.host).toBeUndefined();
    expect(c.ssl).toBeUndefined();

    const s = siteShape.parse({});
    expect(s.host).toBe('localhost:3000');
    expect(s.ssl).toBe(false);
  });

  it('passphrase (site nested)', () => {
    const c = passphraseSchema.parse({});
    expect(c.required).toBeUndefined();
    expect(c.minimum_length).toBeUndefined();

    const s = passphraseShape.parse({});
    expect(s.required).toBe(false);
    expect(s.minimum_length).toBe(4);
    expect(s.maximum_length).toBe(128);
    expect(s.enforce_complexity).toBe(false);
  });

  it('auth', () => {
    const s = authConfigShape.parse({});
    expect(s.mode).toBe('simple');
  });

  it('logging', () => {
    const s = loggingConfigShape.parse({});
    expect(s.default_level).toBe('info');
    expect(s.formatter).toBe('color');
  });
});

describe('contract vs shape: value bounds are absent on contracts, enforced on shapes', () => {
  it('jurisdiction.identifier rejects too-short values only on the shape', () => {
    const tooShort = { identifier: 'x', display_name_i18n_key: 'x', domain: 'x.com' };
    expect(() => jurisdictionSchema.parse(tooShort)).not.toThrow();
    expect(() => jurisdictionShape.parse(tooShort)).toThrow();
  });

  it('emailer.port accepts non-positive numbers only on the contract', () => {
    expect(() => emailerSchema.parse({ port: 0 })).not.toThrow();
    expect(() => emailerShape.parse({ port: 0 })).toThrow();
  });

  it('passphrase.minimum_length out-of-range only fails on the shape', () => {
    expect(() => passphraseSchema.parse({ minimum_length: 300 })).not.toThrow();
    expect(() => passphraseShape.parse({ minimum_length: 300 })).toThrow();
  });

  it('redis db numbers outside 0–15 only fail on the shape', () => {
    expect(() => redisShape.parse({ dbs: { session: 16 } })).toThrow();
    expect(() => redisSchema.parse({ dbs: { session: 16 } })).not.toThrow();
  });
});
