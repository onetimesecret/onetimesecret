// src/utils/diagnostics/resourceRefRegistry.ts
//
// LAYER RULE: src/utils/diagnostics/ is pure policy — it must not import from
// `@sentry/*` nor from `src/plugins/`.
//
// ===========================================================================
// RESOURCE-REF REGISTRY - the exact-match allowlist that lets a schema
// failure carry ONE opaque, server-derived resource pseudonym as a tag.
// ===========================================================================
//
// SIBLING OF `safeFieldRegistry`, SAME CONTRACT
// ---------------------------------------------
// Same key (`${schema}\u0000${path}`), same exact-match lookup, no prefixes,
// no wildcards, and a missing entry is never permission. The difference is
// what an entry authorizes: `safeFieldRegistry` authorizes SHAPE DESCRIPTORS
// derived from a value, this one authorizes forwarding a value VERBATIM -
// which is only defensible because the value is an opaque pseudonym whose
// shape is fully constrained, and because the shape is checked HERE rather
// than trusted from the producer.
//
// WHY THIS EXISTS - the question the event cannot answer without it
// ----------------------------------------------------------------
// A Colonel organization-detail failure attributes to
// `apiRoute:/api/colonel/organizations/:org_id`. That route is
// PARAMETERIZED on purpose (`sanitizeApiRoute`), and the org id is
// deliberately never emitted, so every failing org lands on one aggregate.
// From that aggregate an operator cannot separate:
//
//     "one organization has a broken record"   (a data problem)
//     "every organization is failing"          (a contract/deploy problem)
//
// which is the FIRST question the motivating bug raised - a Colonel detail
// response whose `subscription_period_end` was an Integer epoch where the
// schema expected a string, blanking the page. An opaque ref answers it by
// CARDINALITY ALONE: N events / 1 distinct ref means one org, N events / N
// refs means everyone. Nothing about the org is learned either way.
//
// Note the counting is a DIAGNOSTIC read of events that already exist because
// something broke - it is not usage measurement. No ref is emitted on a
// successful parse, so these tags describe defects and nothing else.
//
// This is the "concrete consumer" whose absence got an earlier
// `organization_ref` deleted from the Ruby side (see the note in
// apps/web/core/views/serializers/diagnostics_serializer.rb): the ref existed
// but no event ever carried an org value, so there was nothing to resolve
// from. This module IS the thing that puts one on an event.
//
// WHY IT READS THE RAW PAYLOAD
// ----------------------------
// The motivating case is a PARSE FAILURE. On failure there is no parsed
// record - `safeParse` returned `success: false` and `result.data` does not
// exist - so a ref read out of a parsed model would be available in exactly
// the case that does not need it. The ref is therefore read from the RAW
// `data` argument that failed, and everything below follows from that:
//
//   * Reading raw means the value is untrusted, so it is SHAPE-VALIDATED
//     against /^[0-9a-f]{16}$/ before it is emitted. A wrong-shaped, longer,
//     uppercase, non-hex, numeric or object value is REFUSED, not forwarded
//     and not coerced. That refusal is what makes reading raw safe: the
//     worst a compromised or drifted producer can do is put 16 hex
//     characters where a ref goes.
//   * Reading raw means traversal must be hostile-input-safe: own properties
//     only (never the prototype chain), plain traversal only, and any throw
//     from a getter or Proxy is swallowed into "no ref".
//
// THE PRIVACY BOUNDARY (read before adding an entry)
// --------------------------------------------------
//  1. OPAQUE, KEYED, ONE-WAY VALUES ONLY. The enrolled field must hold a
//     server-derived pseudonym - the Ruby side's `Onetime::Utils::DiagnosticsRef`
//     shape, 16 lowercase hex. Never an extid, a display name, an email, a
//     billing identifier, a slug, or anything else with meaning outside the
//     keying secret. The shape check enforces the FORMAT; only review
//     enforces that the field is genuinely a pseudonym.
//  2. TAG, NOT EXTRA. Refs are emitted as tags because aggregating by ref is
//     the entire point and `event.extra` is not indexed. Neither surface is
//     scrubbed downstream (see `diagnosticsSurfaceClaims.spec.ts`), so this is
//     an aggregation choice, not a safety one - the value must already be
//     safe before it reaches either.
//  3. INTERNAL/ADMIN SCHEMAS ONLY. Enrollment is per (schema, path). A
//     customer-facing response is not enrolled and emits nothing.
//  4. CARDINALITY. A tag value is an indexed dimension. Bounded here by
//     "one ref per org", which is the same order as the tenant count -
//     acceptable for the internal Colonel surface, and a reason not to
//     enroll a high-cardinality per-request id.

/**
 * Separator for the composite registry key. NUL cannot occur in a schema name
 * or a Zod path segment, so `schema + SEP + path` is unambiguous and two
 * different pairs can never collide into one key.
 *
 * Same construction as `safeFieldRegistry`; the two registries are
 * deliberately independent maps so that enrolling a field for descriptors
 * never implies enrolling it for verbatim forwarding.
 */
const KEY_SEP = '\u0000';

/**
 * The ONLY accepted resource-ref shape: 16 lowercase hex characters, anchored
 * at both ends.
 *
 * This mirrors `Onetime::Utils::DiagnosticsRef`, the same producer behind the
 * `actor_ref` the frontend already puts on `user.id`. Lowercase is required
 * rather than normalized: `applyTagsFromContext` in diagnostics.service.ts
 * lowercases every tag VALUE, so accepting uppercase would let a value that
 * is not a ref arrive looking like one on the wire. Refusing it here means
 * the tag is only ever set from something that was already in ref form.
 */
export const RESOURCE_REF_SHAPE = /^[0-9a-f]{16}$/;

/**
 * The closed set of tag names this registry may emit.
 *
 * Closed on purpose: `gracefulParse` spreads the resolved refs into the
 * `captureException` context bag alongside `schema`, `schemaField`,
 * `apiRoute`, `issueCount` and `issues`, so an unconstrained tag name could
 * shadow one of those. `resourceRefTagNames()` plus the collision spec pin
 * that: every name here is in `TAG_FIELDS` and collides with none of the
 * existing keys.
 */
export type ResourceRefTag = 'organization_ref';

/**
 * THE REGISTRY.
 *
 * Key: `${schemaName}\u0000${dottedRawPath}` - exact match, both halves.
 * `schemaName` is the `context` argument passed to `gracefulParse`;
 * `dottedRawPath` is a path into the RAW payload, so it names wire keys as the
 * server sends them, not as the schema renames them.
 *
 * Value: the tag name the resolved ref is emitted under.
 *
 * Adding an entry is a privacy decision. Review checklist:
 *   - Is the field an opaque, keyed, one-way pseudonym - not an extid, name,
 *     email, slug or billing id?
 *   - Is the schema an INTERNAL/ADMIN surface?
 *   - Does aggregating by this ref answer an operational question that the
 *     parameterized route cannot?
 *   - Is the cardinality bounded by tenants rather than by requests?
 */
const RESOURCE_REFS: ReadonlyMap<string, ResourceRefTag> = new Map<string, ResourceRefTag>([
  // Colonel organization-detail (internal/admin). Answers "one org or every
  // org?" for a route that is parameterized to `:org_id` and therefore cannot.
  // The Ruby side emits null when the deployment has no usable keying secret
  // (the default in dev and test) and older deployments omit the key entirely;
  // both resolve to "no tag" here, which is the same outcome as not enrolled.
  [`ColonelOrganizationDetailResponse${KEY_SEP}record.organization_ref`, 'organization_ref'],
]);

/**
 * Per-schema index over {@link RESOURCE_REFS}, built once at module load.
 *
 * This is a lookup optimization ONLY. The stored path is still compared as a
 * whole string against a whole path when the raw value is read, so the
 * matching semantics are identical to a flat exact-match `Map.get`: no
 * prefixes, no wildcards, no partial-segment matches.
 */
type EnrolledPath = { path: string; tag: ResourceRefTag };

const BY_SCHEMA: ReadonlyMap<string, ReadonlyArray<EnrolledPath>> = (() => {
  const index = new Map<string, EnrolledPath[]>();
  for (const [key, tag] of RESOURCE_REFS) {
    const separator = key.indexOf(KEY_SEP);
    const schema = key.slice(0, separator);
    const path = key.slice(separator + 1);
    const bucket = index.get(schema);
    if (bucket) bucket.push({ path, tag });
    else index.set(schema, [{ path, tag }]);
  }
  return index;
})();

/**
 * Reads one dotted path out of an arbitrary, untrusted value.
 *
 * Deliberately hostile-input-safe, because the input is a payload that just
 * failed to parse and is not known to be well-formed:
 *   - only OWN properties are followed, so `constructor`, `__proto__` and any
 *     other inherited member reads as absent rather than as an object;
 *   - a non-object, null, or missing step ends the walk with `undefined`
 *     instead of throwing;
 *   - a throwing getter or Proxy trap anywhere along the walk is swallowed.
 *
 * @param raw - The value that failed to parse. Any type, including null.
 * @param path - Dotted path, e.g. `record.organization_ref`.
 * @returns The value at that path, or `undefined` if it is not reachable.
 */
function readOwnPath(raw: unknown, path: string): unknown {
  try {
    let current: unknown = raw;
    for (const segment of path.split('.')) {
      if (current === null || typeof current !== 'object') return undefined;
      if (!Object.prototype.hasOwnProperty.call(current, segment)) return undefined;
      current = (current as Record<string, unknown>)[segment];
    }
    return current;
  } catch {
    // A getter or Proxy trap threw. Fail closed: no ref.
    return undefined;
  }
}

/**
 * Resolves the enrolled resource refs for a schema out of its RAW payload.
 *
 * Returns a bag ready to spread into the `captureException` context. It is
 * EMPTY - never a key with an undefined or empty value - whenever there is
 * nothing valid to say, which covers all of:
 *   - the schema is not enrolled (the default for every schema in the app);
 *   - `schema` is undefined (an anonymous `gracefulParse` call);
 *   - the raw payload is not an object, is null, or lacks the path;
 *   - the value is null (the Ruby side's "no usable keying secret" state);
 *   - the value is present but not 16 lowercase hex characters.
 *
 * Emptiness matters: `applyTagsFromContext` skips `undefined` and `null` but
 * would happily `setTag('organization_ref', '')`, an indexed value that means
 * nothing.
 *
 * When two enrolled paths on one schema resolve to the same tag, the first in
 * registry declaration order wins; later ones do not overwrite it.
 *
 * @param schema - The `context` name passed to `gracefulParse`.
 * @param raw - The raw payload that failed validation.
 */
export function resolveResourceRefs(
  schema: string | undefined,
  raw: unknown
): Partial<Record<ResourceRefTag, string>> {
  if (!schema) return {};
  const enrolled = BY_SCHEMA.get(schema);
  if (!enrolled) return {};

  const refs: Partial<Record<ResourceRefTag, string>> = {};
  for (const { path, tag } of enrolled) {
    if (refs[tag] !== undefined) continue;
    const value = readOwnPath(raw, path);
    if (typeof value !== 'string') continue;
    if (!RESOURCE_REF_SHAPE.test(value)) continue;
    refs[tag] = value;
  }
  return refs;
}

/**
 * Diagnostic helper: the enrolled keys in `schema|path -> tag` display form.
 * Exported so a spec can assert the registry has not silently grown.
 */
export function enrolledResourceRefKeys(): string[] {
  return [...RESOURCE_REFS.entries()].map(([key, tag]) => `${key.replace(KEY_SEP, '|')} -> ${tag}`);
}

/** The distinct tag names the registry can emit. */
export function resourceRefTagNames(): ResourceRefTag[] {
  return [...new Set(RESOURCE_REFS.values())];
}
