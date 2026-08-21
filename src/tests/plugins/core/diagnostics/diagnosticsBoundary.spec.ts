// src/tests/plugins/core/diagnostics/diagnosticsBoundary.spec.ts
//
// ACCEPTANCE SUITE — the diagnostics boundary for SCHEMA-VALIDATION events.
//
// WHAT THIS FILE GUARDS
// ---------------------
// A schema-validation failure is the one error class that is *derived from a
// response payload*. That makes it the single most likely carrier of user data
// into Sentry, and it is also the diagnostic we most need to keep (#3424: three
// fixes shipped blind because production discarded the failing field). Both
// properties have to hold at once:
//
//   FORENSICS  — the complete failing field path survives, array indices and
//                all, so the next report names its own cause.
//   PRIVACY    — nothing but the approved, flattened issue metadata leaves the
//                browser: no raw values, no payload fragments, no Zod message
//                strings, no email, no cookies or authorization headers, and no
//                identifier that can be joined back to a person outside Sentry.
//
// WHY THE PIPELINE IS EXERCISED END TO END
// ----------------------------------------
// Every other spec in this directory tests one stage. A leak, though, is a
// property of the *outbound event*, so this file assembles the real thing:
//
//   gracefulParse (production branch)
//     -> the real diagnostics.service captureException
//        -> the real isolated Sentry Scope (tags / extras / user / transaction)
//           -> the real beforeSend built by createDiagnostics
//              -> assertions over the serialized event
//
// Only the Sentry *client* is a mock (it records what it was handed instead of
// POSTing it), plus the router and the bootstrap reader. Nothing between
// gracefulParse and beforeSend is stubbed, so a leak introduced anywhere on
// that path fails here.

import type { ErrorEvent } from '@sentry/core';
import type { RouteLocationNormalizedLoaded, Router } from 'vue-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

// ---------------------------------------------------------------------------
// Mocks — hoisted, since they are referenced from vi.mock factories
// ---------------------------------------------------------------------------

const { mockGetBootstrapValue, MockBrowserClient, getClientInstance, resetClient } = vi.hoisted(
  () => {
    const mockGetBootstrapValue = vi.fn();

    interface CapturedCall {
      error: Error;
      scope: { getScopeData(): Record<string, unknown> };
    }

    let instance: MockBrowserClientType | null = null;

    class MockBrowserClient {
      options: Record<string, unknown>;
      captured: CapturedCall[] = [];

      constructor(options: Record<string, unknown>) {
        this.options = options;
        instance = this as unknown as MockBrowserClientType;
      }

      init = vi.fn();
      close = vi.fn().mockResolvedValue(undefined);
      captureException = vi.fn((error: Error, _hint: unknown, scope: CapturedCall['scope']) => {
        this.captured.push({ error, scope });
        return 'event-id';
      });
      captureMessage = vi.fn();
    }

    type MockBrowserClientType = InstanceType<typeof MockBrowserClient>;

    function getClientInstance(): MockBrowserClientType {
      if (!instance) throw new Error('BrowserClient was never constructed');
      return instance;
    }

    function resetClient(): void {
      instance = null;
    }

    return { mockGetBootstrapValue, MockBrowserClient, getClientInstance, resetClient };
  }
);

// Only the client is replaced. Scope, setCurrentClient, getCurrentScope and the
// integrations stay REAL so the scope data under test is the scope data Sentry
// would actually serialize.
vi.mock('@sentry/browser', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@sentry/browser')>();
  return { ...actual, BrowserClient: MockBrowserClient };
});

vi.mock('@sentry/vue', () => ({
  browserTracingIntegration: vi.fn().mockReturnValue({ name: 'BrowserTracing' }),
}));

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapValue: mockGetBootstrapValue,
}));

vi.mock('@/services/logging.service', () => ({
  loggingService: {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
    banner: vi.fn(),
  },
}));

// Production code, imported after the mocks are in place. diagnostics.service
// and schemaValidation are deliberately NOT mocked — they are the boundary.
import { createDiagnostics } from '@/plugins/core/enableDiagnostics';
import { clearDiagnosticsActor, setDiagnosticsActor } from '@/services/diagnostics.service';
import { gracefulParse } from '@/utils/schemaValidation';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const TEST_HOST = 'example.com';

const baseConfig = {
  sentry: {
    dsn: 'https://key@sentry.io/123',
    environment: 'production',
    release: '1.0.0',
  },
};

/** The opaque, server-derived actor reference (Onetime::Utils::DiagnosticsRef). */
const ACTOR_REF = 'a1b2c3d4e5f60718';
const ACTOR = { actor_ref: ACTOR_REF, actor_scope: 'federated' as const };

/** Values that must never appear in an outbound event, by category. */
const ACTOR_EMAIL = 'tester@example.com';
const ACTOR_OBJID = '01hzk9v4qkq1m2n3p4r5s6t7v8';
const ACTOR_EXTID = 'org_9f3a2b1c8d7e6f50';
const ROUTE_PARAM = 'zx9kq4m2p7w1secretkeyvalue';

/**
 * The parameterized route the transaction name must carry (never the resolved
 * URL). This is a Vue-router path, which is what `scope.setTransactionName`
 * receives in `createDiagnostics` (`to.matched.at(-1)?.path`).
 */
const PARAMETERIZED_ROUTE = '/secret/:secretKey';

/**
 * APPROVED FIELDS — the allowlist this suite enforces.
 *
 * Assert-by-allowlist, not assert-by-denylist: the test enumerates the keys the
 * boundary ACTUALLY emits (recursively, so nested per-issue rows are covered)
 * and fails on anything outside this set. A denylist would pass forever on the
 * one field nobody thought to name.
 *
 * The approved concepts are: schema/context, failing field path, issue code,
 * expected type, received type, issue count, and the parameterized api route.
 * Several spellings per concept are accepted because the *shape* is the
 * contract, not the identifier; `message`, `keys`, `values`, `input`,
 * `received` values, and anything payload-derived are not among them.
 */
const APPROVED_EXTRA_KEYS = new Set([
  // schema / context
  'schema',
  'context',
  // failing field path(s)
  'schemaField',
  'schemaFields',
  'fieldPath',
  'fieldPaths',
  'path',
  'paths',
  // issue code
  'code',
  'codes',
  'issueCode',
  'issueCodes',
  // expected / received TYPE — type names only, never values
  'expected',
  'expectedType',
  'received',
  'receivedType',
  // issue count
  'issueCount',
  'issue_count',
  // HOW MANY unrecognized keys an `unrecognized_keys` issue carried. A count,
  // never a name: the key names are payload-derived and are dropped outright
  // (see `schemaIssueProjection`), and a bare cardinality distinguishes "the
  // backend added a field" from "the client hit the wrong route" without
  // naming anything that came off the wire.
  'key_count',
  // --- safe-field registry descriptors -------------------------------------
  // Emitted ONLY for a `(schema, path)` pair a human explicitly enrolled in
  // `safeFieldRegistry`, and each is a closed vocabulary of shape verdicts
  // derived from the value, never a projection of the value itself.
  //
  //   received_type    typeof/Array verdict: number | string | null | ...
  //                    Same concept as `received` above, under the registry's
  //                    own spelling; a type name carries no payload content.
  'received_type',
  //   numeric_kind     HOW a value encodes a number, if it does: integer |
  //                    float | nan | digit_string | numeric_string |
  //                    iso8601_string | non_numeric_string | null |
  //                    non_numeric. Nine-way enum; it distinguishes the Ruby
  //                    Integer epoch from the `&.to_s` string epoch, which is
  //                    the drift this branch exists to diagnose, and cannot
  //                    express any digit of the value.
  'numeric_kind',
  //   timestamp_format coarse magnitude bucket: below_epoch_range |
  //                    unix_seconds | unix_millis | unix_micros | out_of_range
  //                    | iso8601 | unknown | not_applicable. `unix_seconds`
  //                    alone spans ~2001..5138 CE, so the bucket answers
  //                    "seconds or millis?" and narrows the underlying value
  //                    by essentially nothing.
  'timestamp_format',
  // parameterized api route
  'apiRoute',
  'route',
  // permitted container for the flattened per-issue rows; its own leaf keys are
  // checked recursively against this same set
  'issues',
]);

/** Tags legitimately present on any event from this app. */
const APPROVED_TAG_KEYS = new Set([
  ...APPROVED_EXTRA_KEYS,
  'service',
  'site_host',
  'jurisdiction',
  'actor_scope',
  // --- pseudonymous resource correlation -----------------------------------
  // `organization_ref`: an opaque, server-derived organization pseudonym, 16
  // lowercase hex, emitted ONLY for a (schema, path) pair enrolled in
  // `resourceRefRegistry` and only after that module has shape-checked the
  // raw value. It is deliberately absent from APPROVED_EXTRA_KEYS: it is a
  // tag, and if it ever reaches `event.extra` the extras allowlist above must
  // fail rather than wave it through. `RESOURCE_REF_KEY_IS_TAG_ONLY` below
  // pins that separation.
  //
  // Justified because it answers a question the parameterized route cannot —
  // `apiRoute:/api/colonel/organizations/:org_id` collapses every org onto one
  // aggregate, so "one org broken" and "every org broken" are indistinguishable
  // without it — while carrying no meaning outside the server's keying secret.
  'organization_ref',
]);

/**
 * The tag/extra separation for the resource ref, asserted rather than assumed.
 * If someone adds `organization_ref` to the extras allowlist, this fails.
 */
const RESOURCE_REF_KEY_IS_TAG_ONLY = () => {
  expect(APPROVED_TAG_KEYS.has('organization_ref')).toBe(true);
  expect(APPROVED_EXTRA_KEYS.has('organization_ref')).toBe(false);
};

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

let routerAfterEach: ((to: unknown) => void) | null = null;

function createMockRouter(): Router {
  return {
    resolve: vi.fn((path: string) => ({
      meta: {},
      params: { secretKey: ROUTE_PARAM },
      path,
    })),
    currentRoute: {
      value: {
        params: { secretKey: ROUTE_PARAM },
        meta: {},
        path: PARAMETERIZED_ROUTE,
        matched: [{ path: PARAMETERIZED_ROUTE }],
      } as unknown as RouteLocationNormalizedLoaded,
    },
    afterEach: vi.fn((cb: (to: unknown) => void) => {
      routerAfterEach = cb;
      return () => {};
    }),
  } as unknown as Router;
}

/** The beforeSend the client was actually constructed with. */
function getBeforeSend(): (event: ErrorEvent) => ErrorEvent | null {
  return getClientInstance().options.beforeSend as (event: ErrorEvent) => ErrorEvent | null;
}

interface ScopeData {
  tags: Record<string, unknown>;
  extra: Record<string, unknown>;
  user: Record<string, unknown>;
  transactionName?: string;
}

/**
 * Assembles the event Sentry would build from the captured error plus the scope
 * it was captured with, then runs the real beforeSend over it.
 *
 * `request` mirrors what httpContextIntegration attaches in a browser: the
 * resolved URL and the referrer. Nothing else is added, which is itself an
 * assertion target (no cookies, no authorization header, no body).
 */
function captureAndSend(
  schema: z.ZodType,
  payload: unknown,
  context = 'SecretResponse'
): { raw: ErrorEvent; sent: ErrorEvent; scopeData: ScopeData } {
  const client = getClientInstance();
  client.captured.length = 0;

  gracefulParse(schema, payload, context);

  expect(client.captureException).toHaveBeenCalled();
  const call = client.captured[0];
  const scopeData = call.scope.getScopeData() as unknown as ScopeData;

  const raw: ErrorEvent = {
    exception: { values: [{ type: call.error.name, value: call.error.message }] },
    tags: { ...scopeData.tags } as ErrorEvent['tags'],
    extra: { ...scopeData.extra },
    user: Object.keys(scopeData.user ?? {}).length > 0 ? { ...scopeData.user } : undefined,
    transaction: scopeData.transactionName,
    request: {
      url: `https://${TEST_HOST}${PARAMETERIZED_ROUTE.replace(':secretKey', ROUTE_PARAM)}`,
      headers: { Referer: `https://${TEST_HOST}/receipt/${ROUTE_PARAM}` },
    },
  };

  const sent = getBeforeSend()(structuredCloneEvent(raw)) as ErrorEvent;
  return { raw, sent, scopeData };
}

/** Deep copy that survives the plain objects an event is made of. */
function structuredCloneEvent(event: ErrorEvent): ErrorEvent {
  return JSON.parse(JSON.stringify(event)) as ErrorEvent;
}

/** Every key name appearing anywhere in a value, arrays included. */
function collectKeys(value: unknown, acc: Set<string> = new Set()): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) collectKeys(item, acc);
    return acc;
  }
  if (value && typeof value === 'object') {
    for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
      acc.add(key);
      collectKeys(child, acc);
    }
  }
  return acc;
}

/** The whole outbound event as one string, for absence assertions. */
function serialize(event: ErrorEvent): string {
  return JSON.stringify(event);
}

// ---------------------------------------------------------------------------
// Schemas under test — wire-shaped, deliberately awkward
// ---------------------------------------------------------------------------

/** 4-level path with an array index: record.items.0.nested.field */
const deepSchema = z.object({
  record: z.object({
    items: z.array(z.object({ nested: z.object({ field: z.string() }) })),
  }),
});

function deepPayload(field: unknown = 12345) {
  return { record: { items: [{ nested: { field } }] } };
}

/** Same shape, but the leaf must be a number — so a raw STRING value fails. */
const deepNumericSchema = z.object({
  record: z.object({
    items: z.array(z.object({ nested: z.object({ field: z.number() }) })),
  }),
});

/**
 * A schema whose failure message embeds the received value. Zod v4's built-in
 * messages happen not to interpolate the input, but a `custom` issue, a
 * refinement with a message function, and any hand-written `error` callback all
 * do — and this codebase is free to add one at any time. The boundary must be
 * safe by construction, not by luck.
 */
function messageEmbeddingSchema(prefix: string) {
  return z.object({
    record: z.object({
      token: z.any().superRefine((val, ctx) => {
        ctx.addIssue({ code: 'custom', message: `${prefix} ${String(val)}` });
      }),
    }),
  });
}

/**
 * Strict object: an extra wire key raises `unrecognized_keys`, whose projected
 * row is the ONLY producer of `key_count`. The payload key name below is the
 * leak this row is engineered around - the count survives, the name does not.
 */
const strictSchema = z.strictObject({ id: z.string() });

function strictPayload() {
  return { id: 'x', authorization_token: 'sk_live_XKCD', tenant_owner_email: ACTOR_EMAIL };
}

/**
 * The Colonel row this whole branch exists for, and the ONLY payload shape in
 * this app that reaches the safe-field registry. `record.subscription_period_end`
 * is enrolled in `safeFieldRegistry`, so its projected row carries the three
 * extra shape descriptors (`received_type`, `numeric_kind`, `timestamp_format`)
 * that no other fixture here can produce.
 *
 * The value is the raw Ruby Integer epoch the pre-5f5a8a5732 Colonel emitted
 * against a schema that declares a string - i.e. the exact production drift.
 */
const COLONEL_CONTEXT = 'ColonelOrganizationDetailResponse';

const colonelSchema = z.object({
  record: z.object({ subscription_period_end: z.string() }),
});

/** Chosen so the magnitude bucket resolves to `unix_seconds`. */
const COLONEL_EPOCH = 1772940425;

function colonelPayload(value: unknown = COLONEL_EPOCH) {
  return { record: { subscription_period_end: value } };
}

/**
 * THE PSEUDONYMOUS ORGANIZATION REF.
 *
 * Server-derived, opaque, 16 lowercase hex — the `Onetime::Utils::DiagnosticsRef`
 * shape, the same producer behind `actor_ref`. It is the ONE payload-derived
 * value the boundary forwards verbatim, and only for the enrolled Colonel
 * schema.
 */
const ORG_REF = 'b4c2a90f13e5d867';

/** Organization-identifying values that must never reach an event. */
const ORG_DISPLAY_NAME = 'Acme Holdings BV';
const ORG_CONTACT_EMAIL = 'billing-contact@example.com';
const ORG_BILLING_EMAIL = 'ap@example.com';
const ORG_STRIPE_CUSTOMER = 'cus_QZ12345abcde';
const ORG_STRIPE_SUB = 'sub_1PZ99xyzABCD';
const ORG_INTERNAL_ID = 'org_internal_00112233';

/**
 * The realistic failing Colonel payload: the whole sensitive organization
 * record — extid, display name, owner/contact/billing emails, both stripe
 * identifiers — alongside the ref, with the epoch drift that fails the parse.
 *
 * The suite asserts that exactly one field of this object reaches the event.
 * `ACTOR_EXTID` doubles as the org extid here so the existing
 * "never substitutes an email, extid or raw objid" case covers it too.
 */
function colonelOrgPayload(ref: unknown = ORG_REF, includeRef = true) {
  const record: Record<string, unknown> = {
    org_id: ORG_INTERNAL_ID,
    extid: ACTOR_EXTID,
    display_name: ORG_DISPLAY_NAME,
    contact_email: ORG_CONTACT_EMAIL,
    owner_id: ACTOR_OBJID,
    owner_email: ACTOR_EMAIL,
    billing_email: ORG_BILLING_EMAIL,
    stripe_customer_id: ORG_STRIPE_CUSTOMER,
    stripe_subscription_id: ORG_STRIPE_SUB,
    subscription_period_end: COLONEL_EPOCH,
  };
  if (includeRef) record.organization_ref = ref;
  return { record };
}

/** Every organization-identifying value in {@link colonelOrgPayload}. */
const ORG_IDENTIFYING_VALUES = [
  ACTOR_EXTID,
  ORG_INTERNAL_ID,
  ORG_DISPLAY_NAME,
  ORG_CONTACT_EMAIL,
  ORG_BILLING_EMAIL,
  ACTOR_EMAIL,
  ACTOR_OBJID,
  ORG_STRIPE_CUSTOMER,
  ORG_STRIPE_SUB,
];

/**
 * PAYLOAD SHAPES THE ALLOWLIST MUST BE PROVEN AGAINST.
 *
 * An acceptance suite whose assertions only ever see ONE payload shape proves
 * only that one shape. Every projector branch that can add a key to an emitted
 * row is represented here, so the allowlist assertions below run over the union
 * of keys the boundary can actually produce - not over the single
 * `invalid_type` row that happens to be cheapest to build.
 */
const BOUNDARY_CASES: ReadonlyArray<{
  name: string;
  schema: z.ZodType;
  payload: unknown;
  context: string;
}> = [
  {
    name: 'invalid_type on an unenrolled schema',
    schema: deepSchema,
    payload: deepPayload(),
    context: 'SecretResponse',
  },
  {
    name: 'unrecognized_keys on a strictObject (emits key_count)',
    schema: strictSchema,
    payload: strictPayload(),
    context: 'SecretResponse',
  },
  {
    name: 'enrolled Colonel field (emits registry descriptors)',
    schema: colonelSchema,
    payload: colonelPayload(),
    context: COLONEL_CONTEXT,
  },
  {
    name: 'enrolled Colonel field, coerced string form',
    schema: z.object({ record: z.object({ subscription_period_end: z.number() }) }),
    payload: colonelPayload(String(COLONEL_EPOCH)),
    context: COLONEL_CONTEXT,
  },
  {
    name: 'enrolled Colonel response carrying an organization_ref',
    schema: colonelSchema,
    payload: colonelOrgPayload(),
    context: COLONEL_CONTEXT,
  },
  {
    name: 'custom refinement issue (emits issueCode)',
    schema: messageEmbeddingSchema('owner not found:'),
    payload: { record: { token: ACTOR_EMAIL } },
    context: 'SecretResponse',
  },
  {
    name: 'invalid_value / too_small / invalid_format (emits expected)',
    schema: z.object({
      state: z.enum(['ok', 'stale']),
      nickname: z.string().min(8),
      contact: z.string().email(),
    }),
    payload: { state: 'burned', nickname: 'ab', contact: 'not-an-email' },
    context: 'SecretResponse',
  },
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('the diagnostics boundary — captured schema-validation events', () => {
  const originalConsoleDebug = console.debug;

  beforeEach(() => {
    vi.clearAllMocks();
    resetClient();
    routerAfterEach = null;
    console.debug = vi.fn();
    console.error = vi.fn();

    // Production branch of gracefulParse: dev/test logs to console instead of
    // capturing, so the boundary under test only exists here.
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('DEV', false as never);

    // Anonymous bootstrap; identity is applied explicitly below.
    mockGetBootstrapValue.mockReturnValue(null);

    const plugin = createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });
    // install() wires the REAL diagnostics.service to the REAL isolated scope.
    (plugin as { install: (app: unknown) => void }).install({
      provide: vi.fn(),
      unmount: vi.fn(),
    });

    // Navigation stamps the parameterized route on the isolated scope.
    routerAfterEach?.({ matched: [{ path: PARAMETERIZED_ROUTE }], path: PARAMETERIZED_ROUTE });

    setDiagnosticsActor(ACTOR);
  });

  afterEach(() => {
    clearDiagnosticsActor();
    console.debug = originalConsoleDebug;
    vi.unstubAllEnvs();
  });

  // =========================================================================
  // Forensics — #3424 regression guard
  // =========================================================================
  describe('field-path fidelity', () => {
    it('preserves the complete path of a deeply nested array element', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload());

      expect(serialize(sent)).toContain('record.items.0.nested.field');
    });

    it('never collapses a traversed container to [Array] or [Object]', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload());
      const wire = serialize(sent);

      expect(wire).not.toContain('[Array]');
      expect(wire).not.toContain('[Object]');
      expect(wire).not.toContain('record.items.[');
    });

    it('reports every failing path, not only the first', () => {
      const schema = z.object({
        record: z.object({
          items: z.array(z.object({ nested: z.object({ field: z.string() }) })),
          state: z.string(),
        }),
      });

      const { sent } = captureAndSend(schema, { record: { items: [{ nested: { field: 1 } }] } });
      const wire = serialize(sent);

      expect(wire).toContain('record.items.0.nested.field');
      expect(wire).toContain('record.state');
    });

    it('carries the issue count and the schema/context name', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload());
      const wire = serialize(sent);

      expect(wire.toLowerCase()).toContain('secretresponse');
      expect(JSON.stringify(sent.extra)).toMatch(/"(issueCount|issue_count)":\s*1/);
    });
  });

  // =========================================================================
  // Allowlist — only the approved flattened issue fields
  // =========================================================================
  describe('approved-field allowlist', () => {
    // Run over EVERY payload shape the projector can produce a distinct row
    // for. The single-fixture version of these assertions passed vacuously for
    // `key_count` and the three registry descriptors, because the one fixture
    // it used emits none of them.
    describe.each(BOUNDARY_CASES)('$name', ({ schema, payload, context }) => {
      it('emits no extras key outside the approved set', () => {
        const { sent } = captureAndSend(schema, payload, context);

        const emitted = [...collectKeys(sent.extra)];
        const unapproved = emitted.filter((key) => !APPROVED_EXTRA_KEYS.has(key));

        expect(unapproved).toEqual([]);
      });

      it('emits no tag outside the approved set', () => {
        const { sent } = captureAndSend(schema, payload, context);

        const emitted = Object.keys(sent.tags ?? {});
        const unapproved = emitted.filter((key) => !APPROVED_TAG_KEYS.has(key));

        expect(unapproved).toEqual([]);
      });

      it('never ships the Zod message string', () => {
        const { sent } = captureAndSend(schema, payload, context);

        expect([...collectKeys(sent.extra)]).not.toContain('message');
        // Zod's default type message, verbatim, is the tell.
        expect(serialize(sent.extra as unknown as ErrorEvent)).not.toContain('Invalid input:');
      });

      it('attaches no cookies, authorization header, or request body', () => {
        const { sent } = captureAndSend(schema, payload, context);
        const keys = [...collectKeys(sent)].map((key) => key.toLowerCase());

        expect(keys).not.toContain('cookies');
        expect(keys).not.toContain('cookie');
        expect(keys).not.toContain('authorization');
        expect(keys).not.toContain('data');
        expect(keys).not.toContain('body');
      });
    });

    // The union across every case, asserted in one place: if a future projector
    // branch introduces a key, it has to be named in APPROVED_EXTRA_KEYS before
    // this passes, whichever payload shape produces it.
    it('emits no extras key outside the approved set, across every payload shape', () => {
      const emitted = new Set<string>();
      for (const { schema, payload, context } of BOUNDARY_CASES) {
        const { sent } = captureAndSend(schema, payload, context);
        for (const key of collectKeys(sent.extra)) emitted.add(key);
      }

      expect([...emitted].filter((key) => !APPROVED_EXTRA_KEYS.has(key))).toEqual([]);
    });

    // The counterpart guard: the widened cases must actually EXERCISE the keys
    // that were added to the allowlist for them. Without this, deleting a case
    // would silently return the assertions above to their vacuous state.
    it('actually exercises key_count and the safe-field descriptors', () => {
      const emitted = new Set<string>();
      for (const { schema, payload, context } of BOUNDARY_CASES) {
        const { sent } = captureAndSend(schema, payload, context);
        for (const key of collectKeys(sent.extra)) emitted.add(key);
      }

      for (const key of [
        'key_count',
        'received_type',
        'numeric_kind',
        'timestamp_format',
        'issueCode',
        'expected',
      ]) {
        expect([...emitted]).toContain(key);
      }
    });

    // Same anti-vacuity guard for the tag allowlist. `organization_ref` was
    // added to APPROVED_TAG_KEYS for the enrolled Colonel case; if that case
    // ever stops producing the tag, the tag allowlist has silently widened for
    // nothing and this fails.
    it('actually exercises the organization_ref tag, on the TAG surface only', () => {
      RESOURCE_REF_KEY_IS_TAG_ONLY();

      const tags = new Set<string>();
      const extras = new Set<string>();
      for (const { schema, payload, context } of BOUNDARY_CASES) {
        const { sent } = captureAndSend(schema, payload, context);
        for (const key of Object.keys(sent.tags ?? {})) tags.add(key);
        for (const key of collectKeys(sent.extra)) extras.add(key);
      }

      expect([...tags]).toContain('organization_ref');
      expect([...extras]).not.toContain('organization_ref');
    });

    it('never ships payload-derived key names from unrecognized_keys issues', () => {
      const { sent } = captureAndSend(strictSchema, strictPayload());
      const wire = serialize(sent);

      expect(wire).not.toContain('authorization_token');
      expect(wire).not.toContain('sk_live_XKCD');
      expect(wire).not.toContain('tenant_owner_email');
      // Only how many, never which.
      expect(JSON.stringify(sent.extra)).toContain('"key_count":2');
    });

    it('reports the enrolled Colonel field by SHAPE, never by value', () => {
      const { sent } = captureAndSend(colonelSchema, colonelPayload(), COLONEL_CONTEXT);
      const wire = serialize(sent);

      expect(wire).toContain('record.subscription_period_end');
      expect(wire).toContain('"received_type":"number"');
      expect(wire).toContain('"numeric_kind":"integer"');
      expect(wire).toContain('"timestamp_format":"unix_seconds"');
      // The epoch itself is the value, and never ships.
      expect(wire).not.toContain(String(COLONEL_EPOCH));
    });
  });

  // =========================================================================
  // Pseudonymous references
  // =========================================================================
  describe('pseudonymous actor and resource references', () => {
    it('identifies the actor by the opaque 16-hex ref and nothing else', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload());

      expect(sent.user).toStrictEqual({ id: ACTOR_REF, ip_address: null });
      expect(sent.user?.id).toMatch(/^[0-9a-f]{16}$/);
      expect(sent.tags?.actor_scope).toBe('federated');
    });

    it.each(BOUNDARY_CASES)(
      'never substitutes an email, extid or raw objid for the actor ref ($name)',
      ({ schema, payload, context }) => {
        const { sent } = captureAndSend(schema, payload, context);
        const wire = serialize(sent);

        expect(wire).not.toContain(ACTOR_EMAIL);
        expect(wire).not.toContain(ACTOR_EXTID);
        expect(wire).not.toContain(ACTOR_OBJID);
        expect(wire).not.toMatch(/@/);
      }
    );

    it('strips any non-opaque user field written by another producer', () => {
      const { raw } = captureAndSend(deepSchema, deepPayload());

      const polluted = structuredCloneEvent(raw);
      polluted.user = {
        id: ACTOR_REF,
        email: ACTOR_EMAIL,
        username: 'tester',
        ip_address: '{{auto}}',
        geo: { city: 'Toronto' },
      };

      const sent = getBeforeSend()(polluted) as ErrorEvent;

      expect(sent.user).toStrictEqual({ id: ACTOR_REF, ip_address: null });
    });

    // -----------------------------------------------------------------------
    // organization_ref — the resource half of the same idea
    // -----------------------------------------------------------------------
    //
    // WHAT THIS BUYS. The failing route is emitted parameterized
    // (`/api/colonel/organizations/:org_id`), so every organization's failure
    // lands on ONE aggregate and "one org is broken" is indistinguishable from
    // "every org is broken" — the first question the motivating bug raised.
    // Counting DISTINCT `organization_ref` values over an issue answers it
    // without the event ever carrying an identifier anyone can resolve.
    //
    // WHAT IT COSTS. Nothing resolvable: the ref is keyed and one-way, and the
    // organization's real identifiers are proven absent below even though the
    // payload that failed contained all of them.
    describe('organization_ref', () => {
      it('emits the enrolled ref as a TAG, with the exact value from the raw payload', () => {
        const { sent } = captureAndSend(colonelSchema, colonelOrgPayload(), COLONEL_CONTEXT);

        expect(sent.tags?.organization_ref).toBe(ORG_REF);
        expect(sent.tags?.organization_ref).toMatch(/^[0-9a-f]{16}$/);
        expect(collectKeys(sent.extra)).not.toContain('organization_ref');
        expect(JSON.stringify(sent.extra)).not.toContain(ORG_REF);
      });

      it('reads the ref from the RAW payload — the record never parsed', () => {
        // The motivating case. `colonelSchema` requires a string here and the
        // payload carries the Integer epoch, so the parse FAILED and there is
        // no parsed record to read the ref out of. If the implementation ever
        // starts reading a parsed value, this test can no longer produce a tag.
        const payload = colonelOrgPayload();
        expect(colonelSchema.safeParse(payload).success).toBe(false);

        const { sent } = captureAndSend(colonelSchema, payload, COLONEL_CONTEXT);

        expect(sent.tags?.organization_ref).toBe(ORG_REF);
        // And the failure itself is still fully diagnosable alongside it.
        expect(serialize(sent)).toContain('record.subscription_period_end');
      });

      it('emits NOTHING for an unenrolled schema with an identical-looking ref', () => {
        // Byte-identical payload, different context name. Fail closed.
        const { sent } = captureAndSend(colonelSchema, colonelOrgPayload(), 'SecretResponse');

        expect(sent.tags?.organization_ref).toBeUndefined();
        expect(serialize(sent)).not.toContain(ORG_REF);
      });

      describe.each([
        { name: 'too short', ref: 'b4c2a90f13e5d86' },
        { name: 'too long', ref: 'b4c2a90f13e5d8671' },
        { name: 'uppercase', ref: 'B4C2A90F13E5D867' },
        { name: 'non-hex', ref: 'zzzzzzzzzzzzzzzz' },
        { name: 'a number', ref: 1772940425 },
        { name: 'an object', ref: { ref: ORG_REF } },
        { name: 'an array', ref: [ORG_REF] },
        { name: 'an org extid', ref: ACTOR_EXTID },
        { name: 'an email', ref: ACTOR_EMAIL },
        { name: 'empty string', ref: '' },
        { name: 'null (no keying secret)', ref: null },
      ])('refuses a malformed ref: $name', ({ ref }) => {
        it('sets no organization_ref tag and forwards nothing', () => {
          const { sent } = captureAndSend(
            colonelSchema,
            colonelOrgPayload(ref),
            COLONEL_CONTEXT
          );

          expect(sent.tags?.organization_ref).toBeUndefined();
          expect(collectKeys(sent.extra)).not.toContain('organization_ref');
          if (typeof ref === 'string' && ref.length > 0) {
            expect(serialize(sent)).not.toContain(ref);
          }
        });
      });

      it('sets no tag when the key is absent entirely (older backend)', () => {
        const { sent } = captureAndSend(
          colonelSchema,
          colonelOrgPayload(undefined, false),
          COLONEL_CONTEXT
        );

        expect(sent.tags?.organization_ref).toBeUndefined();
      });

      it('never ships the org extid, name, emails, owner id or stripe ids', () => {
        const { sent } = captureAndSend(colonelSchema, colonelOrgPayload(), COLONEL_CONTEXT);
        const wire = serialize(sent);

        for (const value of ORG_IDENTIFYING_VALUES) {
          expect(wire).not.toContain(value);
        }
        expect(wire).not.toContain('stripe');
        expect(wire).not.toMatch(/cus_|sub_/);
        // The only thing that DID survive from that payload:
        expect(sent.tags?.organization_ref).toBe(ORG_REF);
      });

      it('does not throw when the raw payload is not an object at all', () => {
        expect(() => captureAndSend(colonelSchema, 'not-an-object', COLONEL_CONTEXT)).not.toThrow();
        expect(() => captureAndSend(colonelSchema, null, COLONEL_CONTEXT)).not.toThrow();

        const { sent } = captureAndSend(colonelSchema, null, COLONEL_CONTEXT);
        expect(sent.tags?.organization_ref).toBeUndefined();
      });
    });

    it('names the route by its parameterized path, never the resolved URL', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload());

      expect(sent.transaction).toBe(PARAMETERIZED_ROUTE);
      expect(sent.transaction).not.toContain(ROUTE_PARAM);
    });
  });

  // =========================================================================
  // Scrubbing
  // =========================================================================
  describe('scrubbing', () => {
    it('scrubs an email out of the exception message', () => {
      const schema = messageEmbeddingSchema('owner not found:');

      const { sent } = captureAndSend(schema, { record: { token: ACTOR_EMAIL } });

      expect(sent.exception?.values?.[0].value).toContain('[EMAIL_REDACTED]');
      expect(sent.exception?.values?.[0].value).not.toContain(ACTOR_EMAIL);
    });

    it('keeps an email out of the event entirely, not just out of the message', () => {
      const schema = messageEmbeddingSchema('owner not found:');

      const { sent } = captureAndSend(schema, { record: { token: ACTOR_EMAIL } });

      expect(serialize(sent)).not.toContain(ACTOR_EMAIL);
    });

    it('scrubs the resolved route-param value from request.url and the referrer', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload());

      expect(sent.request?.url).not.toContain(ROUTE_PARAM);
      expect(sent.request?.url).toContain('[REDACTED]');
      expect(JSON.stringify(sent.request?.headers)).not.toContain(ROUTE_PARAM);
    });
  });

  // =========================================================================
  // Omission — raw values, payloads, secrets, credentials
  // =========================================================================
  describe('raw values and credentials are omitted', () => {
    it('never ships a secret embedded in a Zod issue message', () => {
      const secret = 'sk_live_51H8xQe0000LEAKME';
      const schema = messageEmbeddingSchema('rejected token');

      const { sent } = captureAndSend(schema, { record: { token: secret } });

      expect(serialize(sent)).not.toContain(secret);
      expect(serialize(sent)).not.toContain('sk_live_');
    });

    it('never ships the raw failing value for a type mismatch', () => {
      const rawValue = 'RAW-PAYLOAD-VALUE-9f3a2b';

      const { sent } = captureAndSend(deepNumericSchema, deepPayload(rawValue));

      expect(serialize(sent)).not.toContain(rawValue);
    });

    it('reports the received TYPE rather than the received value', () => {
      const { sent } = captureAndSend(deepSchema, deepPayload(12345));
      const wire = serialize(sent);

      // The type name is diagnostic and approved; the value is not.
      expect(wire).toContain('string');
      expect(wire).not.toContain('12345');
    });
  });

  // =========================================================================
  // Logout
  // =========================================================================
  describe('actor context after logout', () => {
    it('clears the user and the actor_scope tag, so later captures are anonymous', () => {
      clearDiagnosticsActor();

      const { sent } = captureAndSend(deepSchema, deepPayload());

      expect(sent.user).toBeUndefined();
      expect(sent.tags?.actor_scope).toBeUndefined();
      expect(serialize(sent)).not.toContain(ACTOR_REF);
    });

    it('does not resurrect the previous actor on the next capture', () => {
      captureAndSend(deepSchema, deepPayload());
      clearDiagnosticsActor();

      const { sent } = captureAndSend(deepSchema, deepPayload());

      expect(serialize(sent)).not.toContain(ACTOR_REF);
    });
  });
});
