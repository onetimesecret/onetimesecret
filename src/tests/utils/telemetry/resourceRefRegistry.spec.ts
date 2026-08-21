// src/tests/utils/telemetry/resourceRefRegistry.spec.ts
//
// THE FAIL-CLOSED PROOFS for pseudonymous resource correlation.
//
// `resourceRefRegistry` is the ONE place in the schema-telemetry path that
// forwards a value read out of a failing payload verbatim. Everything that
// makes that defensible is a claim about refusal — an unenrolled schema
// refuses, a wrong-shaped value refuses, a hostile payload refuses without
// throwing — so every one of those claims is executed here rather than
// asserted in prose.
//
// The end-to-end counterpart (real Sentry scope, real beforeSend, whole event
// serialized) is `src/tests/plugins/core/diagnostics/telemetryBoundary.spec.ts`.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

vi.mock('@/services/logging.service', () => ({
  loggingService: { error: vi.fn(), warn: vi.fn(), info: vi.fn(), debug: vi.fn(), banner: vi.fn() },
}));

import type { BrowserClient, Scope } from '@sentry/vue';
import { captureException, initDiagnostics } from '@/services/diagnostics.service';
import { colonelOrganizationDetailRecordSchema } from '@/schemas/api/internal/responses/colonel-organizations';
import { gracefulParse } from '@/utils/schemaValidation';
import {
  enrolledResourceRefKeys,
  resolveResourceRefs,
  resourceRefTagNames,
  RESOURCE_REF_SHAPE,
} from '@/utils/telemetry/resourceRefRegistry';

/** The enrolled schema name, spelled exactly as `gracefulParse` receives it. */
const ENROLLED = 'ColonelOrganizationDetailResponse';

/** A well-formed ref: 16 lowercase hex, the `Onetime::Utils::TelemetryRef` shape. */
const ORG_REF = 'b4c2a90f13e5d867';

/** Values an operator must never see on an event, present in every fixture below. */
const ORG_EXTID = 'org_9f3a2b1c8d7e6f50';
const OWNER_EMAIL = 'owner@example.com';
const CONTACT_EMAIL = 'billing-contact@example.com';
const BILLING_EMAIL = 'ap@example.com';
const DISPLAY_NAME = 'Acme Holdings BV';
const STRIPE_CUSTOMER = 'cus_QZ12345abcde';
const STRIPE_SUB = 'sub_1PZ99xyzABCD';

/** A raw Colonel detail payload — the whole sensitive record, plus the ref. */
function colonelRaw(ref: unknown, includeRef = true): Record<string, unknown> {
  const record: Record<string, unknown> = {
    org_id: 'org_internal_00112233',
    extid: ORG_EXTID,
    display_name: DISPLAY_NAME,
    description: 'Primary billing org',
    contact_email: CONTACT_EMAIL,
    owner_id: 'cust_0011223344556677',
    owner_email: OWNER_EMAIL,
    billing_email: BILLING_EMAIL,
    stripe_customer_id: STRIPE_CUSTOMER,
    stripe_subscription_id: STRIPE_SUB,
    // The drift that motivated the branch: an Integer epoch where the original
    // schema wanted a string.
    subscription_period_end: 1772940425,
  };
  if (includeRef) record.organization_ref = ref;
  return { record };
}

// ---------------------------------------------------------------------------
// Pure resolution
// ---------------------------------------------------------------------------

describe('resolveResourceRefs — enrollment is exact-match and fail-closed', () => {
  it('resolves the enrolled (schema, path) pair from a RAW payload', () => {
    expect(resolveResourceRefs(ENROLLED, colonelRaw(ORG_REF))).toEqual({
      organization_ref: ORG_REF,
    });
  });

  it('emits nothing for an UNenrolled schema carrying an identical-looking ref', () => {
    // Byte-identical payload; only the schema name differs.
    expect(resolveResourceRefs('SecretResponse', colonelRaw(ORG_REF))).toEqual({});
    expect(resolveResourceRefs('ColonelOrganizationsResponse', colonelRaw(ORG_REF))).toEqual({});
    // Case and near-misses are not matches either.
    expect(resolveResourceRefs(ENROLLED.toLowerCase(), colonelRaw(ORG_REF))).toEqual({});
    expect(resolveResourceRefs(`${ENROLLED}V2`, colonelRaw(ORG_REF))).toEqual({});
  });

  it('emits nothing when no schema name was passed at all', () => {
    expect(resolveResourceRefs(undefined, colonelRaw(ORG_REF))).toEqual({});
    expect(resolveResourceRefs('', colonelRaw(ORG_REF))).toEqual({});
  });

  it('does NOT match by prefix, suffix or a differently-nested path', () => {
    // Enrolled path is exactly `record.organization_ref`.
    expect(resolveResourceRefs(ENROLLED, { organization_ref: ORG_REF })).toEqual({});
    expect(resolveResourceRefs(ENROLLED, { record: { org: { organization_ref: ORG_REF } } })).toEqual(
      {}
    );
    expect(resolveResourceRefs(ENROLLED, { records: { organization_ref: ORG_REF } })).toEqual({});
    expect(
      resolveResourceRefs(ENROLLED, { record: { organization_ref_v2: ORG_REF } })
    ).toEqual({});
  });
});

describe('resolveResourceRefs — a value is refused unless it is exactly 16 lowercase hex', () => {
  const REFUSED: ReadonlyArray<{ name: string; value: unknown }> = [
    { name: 'too short (15)', value: 'b4c2a90f13e5d86' },
    { name: 'too long (17)', value: 'b4c2a90f13e5d8671' },
    { name: 'uppercase hex', value: 'B4C2A90F13E5D867' },
    { name: 'mixed case', value: 'b4C2a90f13e5d867' },
    { name: 'non-hex letters', value: 'zzzzzzzzzzzzzzzz' },
    { name: 'hex with a separator', value: 'b4c2-a90f-13e5-d8' },
    { name: 'leading whitespace', value: ' b4c2a90f13e5d867' },
    { name: 'trailing newline', value: 'b4c2a90f13e5d867\n' },
    { name: 'ref plus an email', value: `b4c2a90f13e5d867 ${OWNER_EMAIL}` },
    { name: 'an org extid', value: ORG_EXTID },
    { name: 'a stripe id', value: STRIPE_CUSTOMER },
    { name: 'an email', value: OWNER_EMAIL },
    { name: 'empty string', value: '' },
    { name: 'a number that looks hexish', value: 1772940425 },
    { name: 'a bigint', value: 10n },
    { name: 'a boolean', value: true },
    { name: 'an object', value: { toString: () => ORG_REF } },
    { name: 'an array holding a ref', value: [ORG_REF] },
    { name: 'a function returning a ref', value: () => ORG_REF },
    { name: 'null (no keying secret — the dev/test default)', value: null },
    { name: 'explicit undefined', value: undefined },
  ];

  it.each(REFUSED)('refuses $name', ({ value }) => {
    expect(resolveResourceRefs(ENROLLED, colonelRaw(value))).toEqual({});
  });

  it('refuses an ABSENT key (mixed-version backend that predates the field)', () => {
    const raw = colonelRaw(undefined, false);
    expect('organization_ref' in (raw.record as object)).toBe(false);
    expect(resolveResourceRefs(ENROLLED, raw)).toEqual({});
  });

  it('the refusals above are not vacuous: the same call site accepts a real ref', () => {
    expect(resolveResourceRefs(ENROLLED, colonelRaw(ORG_REF))).toEqual({
      organization_ref: ORG_REF,
    });
  });
});

describe('resolveResourceRefs — hostile or malformed raw data never throws', () => {
  const HOSTILE: ReadonlyArray<{ name: string; raw: unknown }> = [
    { name: 'null', raw: null },
    { name: 'undefined', raw: undefined },
    { name: 'a string', raw: 'not an object' },
    { name: 'a number', raw: 42 },
    { name: 'an array', raw: [{ organization_ref: ORG_REF }] },
    { name: 'record is null', raw: { record: null } },
    { name: 'record is a string', raw: { record: 'x' } },
    { name: 'record is an array', raw: { record: [ORG_REF] } },
    { name: 'a cyclic object', raw: (() => {
        const cyclic: Record<string, unknown> = { record: {} };
        (cyclic.record as Record<string, unknown>).self = cyclic;
        return cyclic;
      })() },
  ];

  it.each(HOSTILE)('returns {} for $name', ({ raw }) => {
    expect(() => resolveResourceRefs(ENROLLED, raw)).not.toThrow();
    expect(resolveResourceRefs(ENROLLED, raw)).toEqual({});
  });

  it('swallows a throwing getter rather than letting it escape into error reporting', () => {
    const raw = {
      record: {
        get organization_ref(): string {
          throw new Error('boom');
        },
      },
    };

    expect(() => resolveResourceRefs(ENROLLED, raw)).not.toThrow();
    expect(resolveResourceRefs(ENROLLED, raw)).toEqual({});
  });

  it('reads OWN properties only, so a prototype-supplied ref is not read', () => {
    const record = Object.create({ organization_ref: ORG_REF }) as Record<string, unknown>;
    // Present through the prototype chain...
    expect((record as { organization_ref?: string }).organization_ref).toBe(ORG_REF);
    // ...but not an own property, so the walk refuses it.
    expect(resolveResourceRefs(ENROLLED, { record })).toEqual({});
  });

  it('a __proto__ key in the payload supplies no ref and pollutes nothing', () => {
    // JSON.parse puts `__proto__` on the object as an ordinary OWN key rather
    // than assigning the prototype, so this asserts two things: the walk finds
    // no own `record.organization_ref` (the enrolled path is unchanged by the
    // pollution attempt), and Object.prototype is untouched afterwards.
    const polluted = JSON.parse(`{"record":{"__proto__":{"organization_ref":"${ORG_REF}"}}}`);
    expect(resolveResourceRefs(ENROLLED, polluted)).toEqual({});
    expect(({} as Record<string, unknown>).organization_ref).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Registry contents and tag-name contract
// ---------------------------------------------------------------------------

describe('the registry itself', () => {
  it('has exactly the reviewed enrollment, and has not silently grown', () => {
    expect(enrolledResourceRefKeys()).toEqual([
      'ColonelOrganizationDetailResponse|record.organization_ref -> organization_ref',
    ]);
  });

  it('emits exactly one tag name', () => {
    expect(resourceRefTagNames()).toEqual(['organization_ref']);
  });

  it('the exported shape is anchored at both ends', () => {
    expect(RESOURCE_REF_SHAPE.test(ORG_REF)).toBe(true);
    expect(RESOURCE_REF_SHAPE.test(`x${ORG_REF}`)).toBe(false);
    expect(RESOURCE_REF_SHAPE.test(`${ORG_REF}x`)).toBe(false);
  });

  it('no tag name collides with a key gracefulParse already sends', () => {
    // A collision would silently overwrite one of these in the context bag.
    const existing = ['schema', 'schemaField', 'apiRoute', 'issueCount', 'issues'];
    for (const tag of resourceRefTagNames()) {
      expect(existing).not.toContain(tag as string);
    }
  });
});

// ---------------------------------------------------------------------------
// Surface: tag, not extra
// ---------------------------------------------------------------------------

describe('every registry tag name lands on the TAG surface', () => {
  let recorded: { tags: Record<string, unknown>; extras: Record<string, unknown> };

  function makeScope(): Scope {
    const scope = {
      clone: () => scope,
      setTag: (key: string, value: unknown) => {
        recorded.tags[key] = value;
        return scope;
      },
      setExtras: (values: Record<string, unknown>) => {
        Object.assign(recorded.extras, values);
        return scope;
      },
    };
    return scope as unknown as Scope;
  }

  beforeEach(() => {
    recorded = { tags: {}, extras: {} };
    initDiagnostics(
      { captureException: () => 'id' } as unknown as BrowserClient,
      makeScope()
    );
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('DEV', false as never);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  // Driven off the registry's own names, so adding a tag without adding it to
  // TAG_FIELDS in diagnostics.service.ts fails here instead of shipping into
  // extras unnoticed.
  it.each(resourceRefTagNames())('%s is routed by TAG_FIELDS to setTag', (tag) => {
    captureException(new Error('x'), { [tag]: ORG_REF });

    expect(recorded.tags).toHaveProperty(tag, ORG_REF);
    expect(recorded.extras).not.toHaveProperty(tag);
  });

  it('gracefulParse puts organization_ref on tags and nothing org-identifying anywhere', () => {
    const schema = z.object({ record: z.object({ subscription_period_end: z.string() }) });

    gracefulParse(schema, colonelRaw(ORG_REF), ENROLLED);

    expect(recorded.tags).toHaveProperty('organization_ref', ORG_REF);
    expect(recorded.extras).not.toHaveProperty('organization_ref');

    const wire = JSON.stringify(recorded);
    for (const forbidden of [
      ORG_EXTID,
      OWNER_EMAIL,
      CONTACT_EMAIL,
      BILLING_EMAIL,
      DISPLAY_NAME,
      STRIPE_CUSTOMER,
      STRIPE_SUB,
      'org_internal_00112233',
    ]) {
      expect(wire).not.toContain(forbidden);
    }
  });

  it('an unenrolled schema sets no organization_ref tag from the same payload', () => {
    const schema = z.object({ record: z.object({ subscription_period_end: z.string() }) });

    gracefulParse(schema, colonelRaw(ORG_REF), 'SecretResponse');

    expect(recorded.tags).not.toHaveProperty('organization_ref');
    expect(recorded.extras).not.toHaveProperty('organization_ref');
    expect(JSON.stringify(recorded)).not.toContain(ORG_REF);
  });

  it('a null ref (the dev/test default) sets no tag rather than an empty one', () => {
    const schema = z.object({ record: z.object({ subscription_period_end: z.string() }) });

    gracefulParse(schema, colonelRaw(null), ENROLLED);

    expect(recorded.tags).not.toHaveProperty('organization_ref');
    expect(recorded.extras).not.toHaveProperty('organization_ref');
  });
});

// ---------------------------------------------------------------------------
// The success path: the field must survive the schema, or the wire value is
// stripped before anything can ever read it.
// ---------------------------------------------------------------------------

describe('colonelOrganizationDetailRecordSchema keeps organization_ref', () => {
  function validRecord(extra: Record<string, unknown>): Record<string, unknown> {
    return {
      org_id: 'org_internal_00112233',
      extid: ORG_EXTID,
      display_name: DISPLAY_NAME,
      description: null,
      is_default: false,
      archived: false,
      archived_at: null,
      archived_comment: null,
      contact_email: CONTACT_EMAIL,
      owner_id: 'cust_0011223344556677',
      owner_email: OWNER_EMAIL,
      billing_email: BILLING_EMAIL,
      member_count: 3,
      domain_count: 1,
      created: 1772940000,
      updated: 1772940100,
      planid: 'identity_month',
      stripe_customer_id: STRIPE_CUSTOMER,
      stripe_subscription_id: STRIPE_SUB,
      subscription_status: 'active',
      subscription_period_end: 1772940425,
      billing_email_present: true,
      sync_status: 'in_sync',
      sync_status_reason: null,
      ...extra,
    };
  }

  it('parses and RETAINS a 16-hex ref (a plain z.object would otherwise strip it)', () => {
    const parsed = colonelOrganizationDetailRecordSchema.parse(
      validRecord({ organization_ref: ORG_REF })
    );

    expect(parsed.organization_ref).toBe(ORG_REF);
  });

  it('is a plain z.object, so an UNDECLARED key is stripped — hence the declaration', () => {
    // This is the claim the schema comment makes about why declaring the field
    // is load-bearing: without a declaration the backend could send the ref and
    // no consumer would ever see it.
    const parsed = colonelOrganizationDetailRecordSchema.parse(
      validRecord({ organization_ref_undeclared: ORG_REF })
    );

    expect(parsed).not.toHaveProperty('organization_ref_undeclared');
    expect(JSON.stringify(parsed)).not.toContain(ORG_REF);
  });

  it('accepts null — no usable keying secret', () => {
    const parsed = colonelOrganizationDetailRecordSchema.parse(
      validRecord({ organization_ref: null })
    );

    expect(parsed.organization_ref).toBeNull();
  });

  it('accepts the key being ABSENT — a backend that predates the field', () => {
    const parsed = colonelOrganizationDetailRecordSchema.parse(validRecord({}));

    expect(parsed.organization_ref).toBeUndefined();
  });

  it('none of the three cases fails the whole detail record', () => {
    for (const value of [{ organization_ref: ORG_REF }, { organization_ref: null }, {}]) {
      expect(colonelOrganizationDetailRecordSchema.safeParse(validRecord(value)).success).toBe(true);
    }
  });
});
