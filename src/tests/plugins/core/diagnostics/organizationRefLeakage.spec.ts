// src/tests/plugins/core/diagnostics/organizationRefLeakage.spec.ts
//
// LEAKAGE SUITE — the privacy boundary for `organization_ref`, attacked from
// the outside.
//
// `diagnosticsBoundary.spec.ts` proves the boundary emits only approved keys.
// This file asks the complementary question: given an attacker (or a drifted
// backend) who controls the failing payload, can anything that should stay on
// the server reach the outbound event? It differs from its siblings in three
// ways that matter:
//
//   1. It parses against the REAL production schema
//      (`colonelOrganizationDetailResponseSchema`), not a miniature stand-in,
//      so an enrollment path that stops matching the shipped wire shape fails
//      here.
//   2. Its fixture is a complete Colonel organization record carrying every
//      identifier the privacy rules forbid on the diagnostics surface — extid,
//      org id, display name, description, contact/owner/billing addresses,
//      owner objid, and both `stripe_*` ids — and it asserts each value is
//      absent from the SERIALIZED event, tags, extras, message, exception
//      value and breadcrumbs alike.
//   3. It treats `organization_ref` itself as a smuggling channel and tries
//      to push a value through it: an email, a Stripe key, uppercase and
//      mixed-case hex, off-by-one lengths, whitespace- and newline-padded
//      hex, `hex + ':' + email`, a number whose digits could leak, an array,
//      a `toString`-bearing object, a `String` wrapper, and a
//      prototype-supplied ref.
//
// Only the Sentry client, the router and the bootstrap reader are mocked.
// gracefulParse -> diagnostics.service -> the real isolated Scope -> the real
// beforeSend all run, which matters because beforeSend does NOT scrub
// `event.tags` or `event.extra`: the registry's `/^[0-9a-f]{16}$/` check is
// the last line, not the first of several. Every guard below was confirmed
// load-bearing by mutation (dropping the shape check, the enrollment lookup,
// the own-property walk, the `...resourceRefs` spread, or the `TAG_FIELDS`
// entry each turns tests here red).
import type { ErrorEvent } from '@sentry/core';
import type { RouteLocationNormalizedLoaded, Router } from 'vue-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

const { mockGetBootstrapValue, MockBrowserClient, getClientInstance } = vi.hoisted(() => {
  const mockGetBootstrapValue = vi.fn();
  interface CapturedCall { error: Error; scope: { getScopeData(): Record<string, unknown> } }
  let instance: any = null;
  class MockBrowserClient {
    options: Record<string, unknown>;
    captured: CapturedCall[] = [];
    constructor(options: Record<string, unknown>) { this.options = options; instance = this; }
    init = vi.fn();
    close = vi.fn().mockResolvedValue(undefined);
    captureException = vi.fn((error: Error, _h: unknown, scope: any) => {
      this.captured.push({ error, scope }); return 'id';
    });
    captureMessage = vi.fn();
  }

  function getClientInstance(): any { if (!instance) throw new Error('no client'); return instance; }

  return { mockGetBootstrapValue, MockBrowserClient, getClientInstance };
});

vi.mock('@sentry/browser', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@sentry/browser')>();
  return { ...actual, BrowserClient: MockBrowserClient };
});
vi.mock('@sentry/vue', () => ({ browserTracingIntegration: vi.fn().mockReturnValue({ name: 'BT' }) }));
vi.mock('@/services/bootstrap.service', () => ({ getBootstrapValue: mockGetBootstrapValue }));
vi.mock('@/services/logging.service', () => ({
  loggingService: { error: vi.fn(), warn: vi.fn(), info: vi.fn(), debug: vi.fn(), banner: vi.fn() },
}));

import { createDiagnostics } from '@/plugins/core/enableDiagnostics';
import { gracefulParse } from '@/utils/schemaValidation';
import { colonelOrganizationDetailResponseSchema } from '@/schemas/api/internal/responses/colonel-organizations';
import { diagnosticsActorSchema } from '@/schemas/contracts/bootstrap';
import { resolveResourceRefs, enrolledResourceRefKeys, resourceRefTagNames, RESOURCE_REF_SHAPE } from '@/utils/diagnostics/resourceRefRegistry';

const COLONEL = 'ColonelOrganizationDetailResponse';
const REF = 'b4c2a90f13e5d867';

// ---- the PII that must never leave -----------------------------------------
const PII = {
  extid: 'org_9f3a2b1c8d7e6f50',
  org_id: '01hzk9v4qkq1m2n3p4r5s6t7v8',
  display_name: 'Vandelay Industries GmbH',
  description: 'Latex importer, Berlin office',
  contact_email: 'ops@vandelay-industries.de',
  owner_email: 'art.vandelay@vandelay-industries.de',
  billing_email: 'ap@vandelay-industries.de',
  owner_id: '01hzk9wowner0000000000000',
  stripe_customer_id: 'cus_QhX8Zk3mNpLr2A',
  stripe_subscription_id: 'sub_1PqRsTuVwXyZ0123',
};

function failingPayload(refValue: unknown = REF, extra: Record<string, unknown> = {}) {
  return {
    success: true,
    record: {
      org_id: PII.org_id,
      extid: PII.extid,
      organization_ref: refValue,
      display_name: PII.display_name,
      description: PII.description,
      is_default: false,
      archived: false,
      contact_email: PII.contact_email,
      owner_id: PII.owner_id,
      owner_email: PII.owner_email,
      billing_email: PII.billing_email,
      member_count: 4,
      domain_count: 1,
      planid: 'identity_month',
      stripe_customer_id: PII.stripe_customer_id,
      stripe_subscription_id: PII.stripe_subscription_id,
      subscription_status: 'active',
      // THE MOTIVATING DEFECT: Integer epoch where the schema wants a string.
      subscription_period_end: 1772940425,
      billing_email_present: true,
      ...extra,
    },
    details: {},
  };
}

let _routerAfterEach: ((to: unknown) => void) | null = null;

function createMockRouter(): Router {
  return {
    resolve: vi.fn((path: string) => ({ meta: {}, params: {}, path })),
    currentRoute: { value: { params: {}, meta: {}, path: '/colonel/organizations/:id', matched: [{ path: '/colonel/organizations/:id' }] } as unknown as RouteLocationNormalizedLoaded },
    afterEach: vi.fn((cb: (to: unknown) => void) => { _routerAfterEach = cb; return () => {}; }),
  } as unknown as Router;
}

function boot() {
  mockGetBootstrapValue.mockReturnValue(null);
  const plugin = createDiagnostics({
    host: 'example.com',
    config: { sentry: { dsn: 'https://key@sentry.io/123', environment: 'production', release: '1.0.0' } } as any,
    router: createMockRouter(),
  });
  (plugin as { install: (app: unknown) => void }).install({ provide: vi.fn(), unmount: vi.fn() });
}

function capture(schema: z.ZodType, payload: unknown, context = COLONEL) {
  const client = getClientInstance();
  client.captured.length = 0;
  gracefulParse(schema as any, payload, context);
  if (client.captured.length === 0) return null;
  const call = client.captured[0];
  const sd = call.scope.getScopeData() as any;
  const raw: ErrorEvent = {
    exception: { values: [{ type: call.error.name, value: call.error.message }] },
    message: call.error.message,
    tags: { ...sd.tags },
    extra: { ...sd.extra },
    user: Object.keys(sd.user ?? {}).length > 0 ? { ...sd.user } : undefined,
    breadcrumbs: (sd.breadcrumbs ?? []) as any,
    transaction: sd.transactionName,
    request: { url: `https://example.com/colonel/organizations/${PII.extid}`, headers: { Referer: 'https://example.com/colonel/organizations' } },
  } as ErrorEvent;
  const beforeSend = client.options.beforeSend as (e: ErrorEvent) => ErrorEvent | null;
  const sent = beforeSend(JSON.parse(JSON.stringify(raw))) as ErrorEvent;
  return { raw, sent, str: JSON.stringify(sent) };
}

describe('ADVERSARIAL: organization_ref privacy boundary', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    _routerAfterEach = null;
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('DEV', false as never);
    console.error = vi.fn();
    console.debug = vi.fn();
    boot();
  });

  afterEach(() => { vi.unstubAllEnvs(); });

  it('the real production schema actually rejects the fixture', () => {
    expect(colonelOrganizationDetailResponseSchema.safeParse(failingPayload()).success).toBe(false);
  });

  it('ATTACK 1: no org identity string appears ANYWHERE in the outbound event', () => {
    const r = capture(colonelOrganizationDetailResponseSchema, failingPayload())!;
    expect(r).not.toBeNull();
    for (const [name, value] of Object.entries(PII)) {
      expect(r.str, `leaked ${name}`).not.toContain(value);
    }
    expect(r.str).not.toContain('vandelay');
    expect(r.str).not.toContain('Vandelay');
    expect(r.str).not.toContain('stripe');
    expect(r.str).not.toMatch(/cus_|sub_1|org_9f/);
    // but the ref IS there, as a tag
    expect(r.sent.tags?.organization_ref).toBe(REF);
    expect(JSON.stringify(r.sent.extra)).not.toContain(REF);
  });

  it('ATTACK 1b: the epoch VALUE does not leak either, only its shape', () => {
    const r = capture(colonelOrganizationDetailResponseSchema, failingPayload())!;
    expect(r.str).not.toContain('1772940425');
  });

  const SMUGGLE: Array<[string, unknown]> = [
    ['email', 'art.vandelay@vandelay-industries.de'],
    ['stripe key', 'sk_live_51PqRsTuVwXyZ'],
    ['stripe customer id', 'cus_QhX8Zk3mNpLr2A'],
    ['16 chars non-hex', 'zzzzzzzzzzzzzzzz'],
    ['16 chars mixed', 'b4c2a90f13e5d86Z'],
    ['uppercase hex', 'B4C2A90F13E5D867'],
    ['mixed-case hex', 'b4C2a90F13e5D867'],
    ['15 hex', 'b4c2a90f13e5d86'],
    ['17 hex', 'b4c2a90f13e5d8677'],
    ['hex with newline', 'b4c2a90f13e5d867\n'],
    ['leading space', ' b4c2a90f13e5d867'],
    ['hex+payload', 'b4c2a90f13e5d867:ops@vandelay-industries.de'],
    ['regex anchor bypass \\n prefix', '\nb4c2a90f13e5d867'],
    ['number', 1234567890123456],
    ['bigint-as-number', 9007199254740991],
    ['boolean', true],
    ['array', ['b4c2a90f13e5d867']],
    ['object', { toString: () => 'b4c2a90f13e5d867' }],
    ['nested object', { ref: 'b4c2a90f13e5d867' }],
    ['null', null],
    ['undefined', undefined],
    ['empty string', ''],
    ['extid', 'org_9f3a2b1c8d7e6f50'],
  ];

  it.each(SMUGGLE)('ATTACK 2: refuses %s in organization_ref', (_label, value) => {
    const p: any = failingPayload();
    p.record.organization_ref = value;
    const r = capture(colonelOrganizationDetailResponseSchema, p)!;
    expect(r).not.toBeNull();
    expect(r.sent.tags?.organization_ref).toBeUndefined();
    if (typeof value === 'string' && value.length > 3) {
      expect(r.str).not.toContain(value);
    }
  });

  it('ATTACK 2b: a String object wrapper is refused (typeof !== string)', () => {

    const r = capture(colonelOrganizationDetailResponseSchema, failingPayload(new String(REF) as unknown as string))!;
    expect(r.sent.tags?.organization_ref).toBeUndefined();
  });

  it('ATTACK 3: unenrolled schema with a byte-identical payload emits nothing', () => {
    const r = capture(z.object({ record: z.object({ subscription_period_end: z.string() }) }), failingPayload(), 'SecretResponse')!;
    expect(r.sent.tags?.organization_ref).toBeUndefined();
    expect(r.str).not.toContain(REF);
  });

  it('ATTACK 3b: near-miss schema names fail closed', () => {
    for (const name of ['colonelOrganizationDetail', 'ColonelOrganizationDetail', 'ColonelOrganizationDetailResponse ', 'colonelorganizationdetailresponse', 'ColonelOrganizationDetailResponseX']) {
      const r = capture(z.object({ record: z.object({ subscription_period_end: z.string() }) }), failingPayload(), name)!;
      expect(r.sent.tags?.organization_ref, `leaked under ${name}`).toBeUndefined();
    }
  });

  it('ATTACK 4: prototype-supplied ref is not reachable', () => {
    const proto = { organization_ref: REF };
    const rec = Object.create(proto);
    Object.assign(rec, failingPayload().record);
    delete (rec as any).organization_ref;
    expect((rec as any).organization_ref).toBe(REF); // reachable via chain
    expect(resolveResourceRefs(COLONEL, { record: rec })).toEqual({});
  });

  it('ATTACK 4b: __proto__ smuggling does not pollute or emit', () => {
    const payload = JSON.parse(`{"record":{"__proto__":{"organization_ref":"${REF}"},"subscription_period_end":1}}`);
    expect(resolveResourceRefs(COLONEL, payload)).toEqual({});
    expect(({} as any).organization_ref).toBeUndefined();
  });

  it('ATTACK 5: throwing getter / cyclic / non-object never throws', () => {
    const hostile: any = { record: {} };
    Object.defineProperty(hostile.record, 'organization_ref', { get() { throw new Error('boom'); }, enumerable: true });
    expect(() => resolveResourceRefs(COLONEL, hostile)).not.toThrow();
    expect(resolveResourceRefs(COLONEL, hostile)).toEqual({});
    const cyc: any = { record: { organization_ref: REF } }; cyc.self = cyc;
    expect(resolveResourceRefs(COLONEL, cyc)).toEqual({ organization_ref: REF });
    for (const v of [null, undefined, 'str', 42, [], { record: null }, { record: 'x' }]) {
      expect(() => resolveResourceRefs(COLONEL, v)).not.toThrow();
      expect(resolveResourceRefs(COLONEL, v)).toEqual({});
    }
  });

  it('ATTACK 6: registry has not silently grown; every tag is in TAG_FIELDS', async () => {
    expect(enrolledResourceRefKeys()).toEqual([
      'ColonelOrganizationDetailResponse|record.organization_ref -> organization_ref',
    ]);
    expect(resourceRefTagNames()).toEqual(['organization_ref']);
    const src = await import('node:fs').then((fs) => fs.readFileSync('src/services/diagnostics.service.ts', 'utf8'));
    const tagFields = /const TAG_FIELDS = \[([^\]]*)\]/.exec(src)![1];
    for (const tag of resourceRefTagNames()) expect(tagFields).toContain(`'${tag}'`);
  });

  it('ATTACK 7: bootstrap diagnostics block is still exactly two keys and strict', () => {
    expect(Object.keys((diagnosticsActorSchema as any).shape).sort()).toEqual(['actor_ref', 'actor_scope']);
    expect(diagnosticsActorSchema.safeParse({ actor_ref: 'a1b2c3d4e5f60718', actor_scope: 'federated' }).success).toBe(true);
    expect(diagnosticsActorSchema.safeParse({ actor_ref: 'a1b2c3d4e5f60718', actor_scope: 'federated', organization_ref: REF }).success).toBe(false);
  });

  it('ATTACK 8: shape regex is anchored against multiline bypass', () => {
    expect(RESOURCE_REF_SHAPE.test('b4c2a90f13e5d867\nnasty')).toBe(false);
    expect(RESOURCE_REF_SHAPE.test('nasty\nb4c2a90f13e5d867')).toBe(false);
    expect(RESOURCE_REF_SHAPE.flags).not.toContain('m');
    expect(RESOURCE_REF_SHAPE.flags).not.toContain('g'); // lastIndex statefulness
  });

  it('ATTACK 9: repeated resolution is stateless (no regex lastIndex drift)', () => {
    for (let i = 0; i < 5; i++) {
      expect(resolveResourceRefs(COLONEL, failingPayload())).toEqual({ organization_ref: REF });
    }
  });

  it('ATTACK 10: ref absent / null (dev+test default) emits no empty tag', () => {
    const p: any = failingPayload();
    delete p.record.organization_ref;
    const r = capture(colonelOrganizationDetailResponseSchema, p)!;
    expect(r.sent.tags && 'organization_ref' in r.sent.tags).toBe(false);
  });

  it('ATTACK 15: beforeSend does not scrub tags - the shape check is the last line', () => {
    // Executed rather than assumed: createBeforeSendHandler rewrites messages,
    // request.url, the Referer header, the transaction name and breadcrumbs,
    // but never walks event.tags or event.extra. So nothing downstream would
    // catch a bad ref if the registry let one through.
    const client = getClientInstance();
    const beforeSend = client.options.beforeSend as (e: ErrorEvent) => ErrorEvent | null;
    const probe = beforeSend({
      exception: { values: [{ type: 'Error', value: 'x' }] },
      tags: { organization_ref: PII.owner_email },
      extra: { leaked: PII.stripe_customer_id },
    } as unknown as ErrorEvent) as ErrorEvent;
    expect(probe.tags?.organization_ref).toBe(PII.owner_email);
    expect((probe.extra as Record<string, unknown>).leaked).toBe(PII.stripe_customer_id);
  });

  it('ATTACK 12: path match is exact - a ref at any other path is not read', () => {
    expect(resolveResourceRefs(COLONEL, { organization_ref: REF })).toEqual({});
    expect(resolveResourceRefs(COLONEL, { record: { record: { organization_ref: REF } } })).toEqual({});
    expect(resolveResourceRefs(COLONEL, { details: { members: [{ organization_ref: REF }] } })).toEqual({});
    expect(resolveResourceRefs(COLONEL, { record: { organization_ref_x: REF } })).toEqual({});
    expect(resolveResourceRefs(COLONEL, { 'record.organization_ref': REF })).toEqual({});
  });

  it('ATTACK 13: a numeric ref value does not leak its digits', () => {
    const p: any = failingPayload();
    p.record.organization_ref = 1234567890123456;
    const r = capture(colonelOrganizationDetailResponseSchema, p)!;
    expect(r.str).not.toContain('1234567890123456');
    expect(r.sent.tags?.organization_ref).toBeUndefined();
  });

  it('ATTACK 14: registry entry only names an internal/admin schema', () => {
    for (const key of enrolledResourceRefKeys()) {
      expect(key.startsWith('Colonel')).toBe(true);
    }
  });

  it('ATTACK 11: no other colonel schema is enrolled', async () => {
    const mod = await import('@/schemas/api/internal/responses/colonel-organizations');
    const others = ['ColonelReconcileOrganizationResponse', 'ColonelDeleteOrganizationResponse', 'ColonelTransferOrganizationOwnershipResponse', 'ColonelOrganizationsResponse'];
    for (const name of others) {
      expect(resolveResourceRefs(name, failingPayload())).toEqual({});
    }
    expect(mod).toBeDefined();
  });
});
