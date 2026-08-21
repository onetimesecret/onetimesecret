# The diagnostics privacy boundary

What this application sends to Sentry, what it never sends, and which line of
code enforces each of those.

This is the reference document for the `diagnostics` subsystem. If you are
adding a field to an error event, enrolling a schema field, writing a scrubber,
or reviewing a change that touches any of that, read this first.

Every claim below was checked against the code as it stands on this branch.
Where a protection holds only on some paths, this document says which paths.
Where something is a heuristic rather than a guarantee, it says so. Section 7
is the honest list of what is *not* covered — read it, it is not a formality.

---

## 1. What this subsystem is for

It exists so that **defects can be diagnosed**. When a page blanks, a parse
fails, or an exception escapes, an operator needs enough context in the error
report to find the cause without asking the affected user to reproduce it.

It is explicitly **not**:

- **not analytics** — nothing here answers "how many people used feature X";
- **not metrics** — nothing here is counted, charted, or reported on;
- **not usage measurement or behavioural profiling** — no field emitted by this
  subsystem is read for any purpose other than triaging a specific failure.

That distinction is the tie-breaker for every judgement call in the code. A
field earns its place by making a defect diagnosable, and it pays for itself
only if it carries no personal data. It is why a response **byte count** is
retained on an HTTP breadcrumb (it separates an empty response from a truncated
one from a full-size-but-wrong-shape one) while the response **body** is
dropped outright. "It would be interesting to know" is a refusal, not a
justification.

**Sentry here is self-hosted.** The concern is therefore data minimization
inside our own infrastructure — GDPR hygiene, blast-radius reduction, and not
building a join key between an observability store and a production datastore —
rather than distrust of a third-party vendor. The rules are the same either way,
but the motivation matters when weighing a diagnostic against its cost: an event
too scrubbed to diagnose has no other purpose to fall back on.

There is a second, mirrored boundary on the Ruby side
(`lib/onetime/initializers/setup_diagnostics.rb`) that predates this work. It is
summarised in §7 where it diverges from the frontend.

---

## 2. The layer rule

```
src/utils/diagnostics/          PURE POLICY — decides WHAT may be said
    apiRouteContext.ts          parameterized API routes
    resourceRefRegistry.ts      allowlist for opaque resource pseudonyms
    safeFieldRegistry.ts        allowlist for per-field shape descriptors
    schemaIssueProjection.ts    value-free rendering of a ZodError
    scrubbers.ts                the regex nets
    urlScrubbing.ts             route-param value redaction in URLs

src/plugins/core/diagnostics/   SENTRY WIRING — decides HOW it is sent
    actorIdentity.ts            the Sentry `user` context
    breadcrumbPolicy.ts         breadcrumb allowlists and free-text policy

src/plugins/core/enableDiagnostics.ts
                                the client, and the three outbound handlers
```

**`src/utils/diagnostics/` must not import `@sentry/*` and must not import from
`src/plugins/`.** Every file in that directory carries the rule in its header
comment. The one import that looks like an exception is not one:
`scrubbers.ts` imports `@/generated/sentry-scrub-patterns`, a generated file of
plain `RegExp` literals with no imports of its own.

The two modules that stay in the plugin layer are there because they speak
Sentry's own types — `actorIdentity.ts` writes `Scope.setUser`,
`breadcrumbPolicy.ts` operates on `Breadcrumb`.

`scrubbers.ts` and `urlScrubbing.ts` moved *down* into the util layer on this
branch. Three modules under `src/utils/` already imported the scrubbers, so pure
code sitting in the plugin layer was being pulled downward by the util layer.
The dependency now points one way.

**Practical consequence:** the projection, the registries and the scrubbers are
unit-testable with no Sentry mock at all, and a change to Sentry wiring cannot
silently change what the policy layer permits.

---

## 3. What IS sent

### 3.1 Actor identity — `user` context and `actor_scope`

```
user = { id: "<16 lowercase hex>", ip_address: null }
tags.actor_scope = "federated" | "deployment"
```

That is the complete `user` object. It is built by literal construction in
`applyActorIdentity` (`src/plugins/core/diagnostics/actorIdentity.ts`), never by
spreading the server block, so a new server-side field cannot ride along.

*Why it is needed:* without a stable actor reference, an operator cannot tell
"this crash hits one account" from "this crash hits fifty". That is the first
question asked of any error aggregate, and answering it wrongly changes the
severity assessment.

Anonymous sessions get **nothing** — the server omits the block, and
`applyActorIdentity` calls `setUser(null)`. There is deliberately no generated
fallback or device id; minting one would recreate the cross-session tracking
identifier this design exists to avoid.

### 3.2 Deployment tags

`service` (always `web`), `site_host`, and `jurisdiction` when the regions
feature declares one — set by `applyDeploymentTags` in `enableDiagnostics.ts` on
both the isolated scope and the current scope.

*Why:* multi-region and custom-domain deployments report into one backend; these
tags are how an operator knows which instance produced the event.

### 3.3 Schema-validation diagnostics

Produced by `gracefulParse` (`src/utils/schemaValidation.ts`), which is the main
event producer in this subsystem. It emits, and nothing else:

| Field | Surface | Why it is needed |
|---|---|---|
| `schema` | tag | which contract failed |
| `schemaField` | tag | the failing field path(s), comma-joined, segment-scrubbed — the one indexed dimension you can search on |
| `apiRoute` | tag | *parameterized* endpoint that produced the payload |
| `organization_ref` | tag | opaque org pseudonym, enrolled schemas only (§5) |
| `issueCount` | extra | the TRUE issue total, never the truncated count |
| `issues` | extra | up to 10 flat rows: `path`, `code`, `expected`, `received`, and for a few kinds `key_count` / `issueCode` |

Which of those is a tag and which is an extra is decided by `TAG_FIELDS` in
`src/services/diagnostics.service.ts` — that list is the authority, not any
comment.

The row shape is what made the motivating bug diagnosable: path
`record.subscription_period_end`, code `invalid_type`, expected `string`,
received `number`. **Over-scrubbing is a regression here, not a win.** Issue
#3424 burned three fixes precisely because production discarded the failing
field. Any future tightening that cannot carry that four-part tuple is wrong.

Rows are **flat** — string keys, primitive values, no nesting — because Sentry
normalizes `event.extra` at `normalizeDepth: 3` before transport. Measured:
`normalize(extra, 3)` preserves every row; `normalize(extra, 2)` collapses
`issues` to `["[Object]"]`, silently, with the event still delivered and still
looking healthy. There is zero margin. `normalizeDepth: 3` is pinned *after* the
backend-config spread in `enableDiagnostics.ts` for that reason.

Schema-authored constants **are** emitted, folded into the single `expected`
field: the accepted literal set of an enum, the format name behind an
`invalid_format`, the numeric bound behind `too_small` / `too_big`. Verified by
execution:

```
z.enum(['ok','stale'])  ->  expected: "\"ok\"|\"stale\""
z.email()               ->  expected: "email"
z.string().min(8)       ->  expected: "string >=8"
```

These originate in `.ts` schema source, never on the wire. Dropping them made
`z.email()` and `z.url()` failures byte-identical and left enum drift
undiagnosable — the same bug class this branch exists for. Each one is still run
through `safeConstant`, which refuses the whole field if a scrub pass changes
it, so a schema that ever starts building an enum at runtime fails **closed**.

### 3.4 Parameterized routes, never resolved URLs

`apiRoute` and `event.transaction` both carry a parameterized route:

```
/api/colonel/organizations/org_9f3a2b1c8d7e6f50   <- never sent
/api/colonel/organizations/:org_id                <- what is sent
```

The API-side value comes from the axios request interceptor, which stamps a
module-level slot on every outbound request (`noteApiRequestStarted` →
`setCurrentApiRoute`) and releases it one macrotask after the last in-flight
request settles. The URL is parameterized **on the way in**, so the resolved
form is never retained even in memory. The browser-side value comes from
`router.afterEach`, which stamps `to.matched.at(-1)?.path`.

*Why:* the parameterized form is strictly better for triage (all failures on an
endpoint group into one issue) and carries no tenant reference at all.

### 3.5 Breadcrumbs — metadata about the sequence, not its contents

For `xhr` / `fetch`, `data` is reduced to exactly:
`url`, `method`, `status_code`, `duration`, `request_body_size`,
`response_body_size`, `trace_id`, `span_id`, `request_id`.

For `navigation`: `from`, `to`.

Every retained key also declares a permitted primitive type, and a value of the
wrong type is dropped rather than coerced (`BREADCRUMB_DATA_KEY_TYPES` in
`breadcrumbPolicy.ts`). Verified: `{ request_body_size: '{"password":"hunter2"}',
url: '/x', request_body: 'y' }` reduces to `{ url: '/x' }`.

*Why byte counts stay:* a number of bytes cannot be reversed into a payload and
carries no personal data at any size, and it is the only signal separating an
empty response from a truncated one from a full-size-but-wrong-shape one — three
causes with the same status code.

`duration` is populated from the SDK's breadcrumb **hint**
(`httpBreadcrumbDurationFromHint`), which is where @sentry/browser actually puts
`startTimestamp` / `endTimestamp`. It is folded in *after* the allowlist runs so
it cannot be used to smuggle a key past it.

### 3.6 Free text, scrubbed

Exception values, `event.message`, breadcrumb messages on every category, and
transaction span descriptions all pass through `scrubSensitiveStrings`. Verified
end to end:

```
"user josé@example.com from 203.0.113.5 key sk_live_SUPER_SECRET org org_9f3a2b1c8d7e6f50"
  -> "user [EMAIL_REDACTED] from [IP_REDACTED] key [SECRET_REDACTED] org [ID_REDACTED]"
```

Each net gets its **own sentinel** on purpose. A reader triaging an event needs
to know *what kind* of thing was removed, and the projection surfaces the
sentinel set as `redactionSignals` — the redaction is itself a diagnostic
output.

### 3.7 Request context

`httpContextIntegration` attaches exactly three things — `request.url`,
`request.headers.Referer`, and `request.headers['User-Agent']`. Read out of the
installed SDK (`getHttpRequestData()`), not assumed. The URL and the Referer are
both scrubbed by `scrubCommonEventFields`, which *both* `beforeSend` and
`beforeSendTransaction` call, so errors and transactions get identical
treatment. There is no client-side source for the reporter's IP in a browser at
all.

---

## 4. What is NEVER sent, and what stops it

| Never sent | Enforced by |
|---|---|
| Email, username, display name, geo, segment, or any other key on `user` | `sanitizeEventUser` — `src/plugins/core/diagnostics/actorIdentity.ts`. Whitelists to `{ id, ip_address: null }` and drops `user` entirely unless `id` matches `/^[0-9a-f]{16}$/` |
| An inferred reporter IP | `sendDefaultPii: false` **and** the literal `ip_address: null`, both pinned after the backend-config spread — `enableDiagnostics.ts`. An explicit `null` is not `{{auto}}`, so Sentry relay has nothing to substitute |
| A server-side field the client did not expect | `diagnosticsActorSchema` is a Zod `strictObject` — `src/schemas/contracts/bootstrap.ts`. Any extra key drops the whole block |
| Zod issue messages (built-in *or* custom) | `projectSchemaIssues` — `schemaIssueProjection.ts`. `RawIssueLike` does not declare `message`; the two call sites that read it do so through an explicit cast and keep only sentinels (`collectRedactionSignals`) or a token-class shape (`describeCustomIssue`) |
| `unrecognized_keys` key names (payload-derived) | `buildRow` — `schemaIssueProjection.ts`. Only `key_count` survives. Verified: a strict-object failure on `{ authorization_token: … }` emits `{"code":"unrecognized_keys","key_count":1}` and nothing else |
| `issue.input`, or any payload value | `RawIssueLike` does not declare `input`. `valueAtPath` reads a value only to name its type (`typeNameOf`) or to derive registry descriptors, and discards it |
| `issue.pattern` from `invalid_format` | Never read. `expectedFromFormat` reads `format` only |
| `issue.params` wholesale | `describeCustomIssue` reads only four key names, each gated by `REFINEMENT_ID` and `safeConstant`. (See §7 — this bounds punctuation, not semantics) |
| A payload key appearing as a Zod path segment | `projectPathSegment` — `schemaIssueProjection.ts`. Fails **closed**: anything not provably schema-authored becomes `[REDACTED]`. Verified: `z.record` keyed by `alice@example.com` and `sk_live_51H8xQzABCDEF` both project to `path: "[REDACTED]"`, in the tag *and* in the extras rows |
| A resolved URL in `apiRoute` | `sanitizeApiRoute` — `apiRouteContext.ts`. The single sanitizer both producers go through: parameterize → scrub → cap. Verified: `/api/colonel/organizations/org_9f3a…` → `/api/colonel/organizations/:org_id` |
| Request/response bodies, headers, cookies on `xhr`/`fetch`/`navigation` breadcrumbs | `pickAllowedData` — `breadcrumbPolicy.ts`, applied both at capture time and again at send time |
| Raw console arguments | `applyFreeTextPolicy` — `breadcrumbPolicy.ts`. `data.arguments` is dropped outright, not scrubbed: structured scrubbing of arbitrary nested objects is not something this codebase can guarantee |
| Session replay | Not in the `integrations` array, and `integrations` is pinned after the config spread |
| Trace headers to arbitrary hosts | `tracePropagationTargets` — three anchored entries: relative paths (`/^\/(?!\/)/`, the negative lookahead excludes protocol-relative URLs), localhost, and the display host plus subdomains, anchored at both ends so `example.com.attacker.io` is refused |

### The sharp edge: extras and tags are not scrubbed

`createBeforeSendHandler` scrubs exception values, `event.message`,
`request.url`, the Referer header, `event.transaction`, `event.user`, and
breadcrumbs. **It does not touch `event.extra` and it does not touch
`event.tags`.**

Anything placed on either surface is therefore unscrubbed *by construction* and
must already be safe when it is handed to `captureException`. That is why the
projection is built at the producer rather than filtered at the boundary.

Extras are the *wider* surface (a whole projected structure versus one short
string), but neither is filtered. "It is a tag" never means "something
downstream will clean it".

---

## 5. Pseudonymous references

Two opaque references exist, both derived server-side by
`Onetime::Utils::DiagnosticsRef` (`lib/onetime/utils/diagnostics_ref.rb`):

```
actor_ref = HMAC(secret, "onetime:sentry:v1:actor"        ‖ 0x00 ‖ residency ‖ 0x00 ‖ normalized_email)
org_ref   = HMAC(secret, "onetime:sentry:v1:organization" ‖ 0x00 ‖ residency ‖ 0x00 ‖ org_objid)
```

truncated to 16 hex characters (64 bits) — deliberately half the width of a
federation email hash, so the two are never confusable by shape.

### Why they are keyed, and keyed *this way*

A plain hash of an email is trivially reversible by dictionary. Keying makes the
reference unusable by anyone who does not hold the secret.

The **versioned purpose prefix** is the domain separation. It is what stops an
operator holding an actor ref from testing it against the organization surface,
and it lets diagnostics identity be re-keyed later without touching federation
identity. Verified by execution — the same input string under identical keying
and residency:

```
actor_ref("a@b.com")        -> f4dff32e98633c82
organization_ref("a@b.com") -> 445fff1b62572166
```

The federation `EmailHash` is deliberately **not** reused: that value is
simultaneously a queryable datastore index and a field written into Stripe
customer metadata, so shipping it would hand the diagnostics store a live join
key into billing records.

### Residency: refs deliberately do not correlate across regions

Regional instances share one `FEDERATION_SECRET` by design and report into one
diagnostics backend, and every event is tagged with its `jurisdiction`. A
region-independent ref would therefore emit the identical `user.id` from the EU
and US instances — a ready-made join key proving one data subject is present in
both. That is exactly the inference the jurisdictional-residency architecture
exists to prevent.

So a residency scope is mixed into the derivation unconditionally, resolved in
this order:

1. `DIAGNOSTICS_REF_REGION` — explicit operator pin;
2. `features.regions.current_jurisdiction` (`JURISDICTION`);
3. nothing declared → **the shared key is refused**.

There is no opt-out knob, because an opt-out would exist only to reconstruct the
hazard. Cross-region correlation buys nothing operationally: a stack trace
raised in the EU instance is debugged against the EU instance's code and data.
"Is this the same human as the one erroring in the US?" is a product-analytics
question, and it is not one this data is permitted to answer.

**The safe state is the default.** When no residency resolves, `#keying`
declines `FEDERATION_SECRET` entirely and falls through to `ACCOUNT_ID_SECRET`,
yielding scope `deployment`. Correlation can then only narrow, never widen — and
the emitted label narrows with it, so an operator is never told a ref is
comparable further than it is. Verified by execution:

```
FEDERATION_SECRET only, no residency          -> keying nil, no block emitted
FEDERATION_SECRET + ACCOUNT_ID_SECRET, none   -> {actor_ref: 0efa1786aa7a1bfd, scope: "deployment"}
… + DIAGNOSTICS_REF_REGION=eu                 -> {actor_ref: f4dff32e98633c82, scope: "federated"}
… + DIAGNOSTICS_REF_REGION=us                 -> {actor_ref: aaab2b4fb4313f59, scope: "federated"}
neither secret configured                     -> available? false, nothing emitted
```

Residency is resolved **once per derivation** and threaded inside a `Keying`
value, so the residency mixed into a ref and the scope label emitted beside it
always come from one read of the config. `#digest_ref` additionally refuses to
emit anything if it is ever handed federated keying with no residency, so the
`unscoped` pre-image element can never reach the shared key.

*Not* guaranteed: that two derivations minutes apart agree. An operator who
changes the declared jurisdiction has re-keyed diagnostics identity, and that
splits the actor by design.

### Where each ref travels

`actor_ref` rides the bootstrap `diagnostics_actor` block — per session, exactly
two keys, parsed by a strict schema.

`organization_ref` rides the **colonel organization-detail response record** —
per resource, not per session. It deliberately does not travel in the actor
block: mechanically it would be a third key in a `strictObject` and would drop
the actor identity entirely; semantically a session has one actor but touches
many organizations, so whichever org was current at render time would be tagged
onto every later event in the session, including events about other orgs.

The frontend recovers it from the **raw** payload, because the motivating case
is a parse *failure* — on failure there is no parsed record to read from. That
is why `resolveResourceRefs` shape-validates against `/^[0-9a-f]{16}$/` rather
than trusting the producer, and why its traversal follows own properties only
and swallows any throwing getter or Proxy trap. Verified:

```
{record:{organization_ref:"a1b2c3d4e5f60718"}}  -> {organization_ref:"a1b2c3d4e5f60718"}
{record:{organization_ref:"A1B2C3D4E5F60718"}}  -> {}     (uppercase refused)
same value, unenrolled schema                    -> {}
```

*What it buys:* the route is parameterized to `:org_id` on purpose, so every
failing org lands on one aggregate. The ref separates "one organization has a
broken record" from "every organization is failing" **by cardinality alone** —
N events / 1 distinct ref versus N events / N refs. Nothing about the
organization is learned either way, and no ref is emitted on a successful parse,
so these tags describe defects and nothing else.

### The honest caveat

**A keyed pseudonym is still personal data under GDPR Recital 26.** Pseudonymisation
reduces exposure; it does not make the data anonymous, and it does not remove
these events from the scope of data-protection obligations.

Concretely, what a holder of the Sentry data *can* still do: link every event
carrying the same ref to one person, count how many distinct people are affected
by a defect, and observe activity patterns per ref over time. What they cannot
do without the keying secret is recover the email, the objid, or any other
identifier — and holding a ref does not let them test it against a different
surface, because the purpose prefixes separate the namespaces.

Anyone with access to both the Sentry store and the keying secret can re-link a
ref to an account. That is a real property of the design, not an oversight: the
secret is the control, and it must be treated as one.

---

## 6. Extending the boundary

### Adding a safe field (shape descriptors)

`src/utils/diagnostics/safeFieldRegistry.ts` is the **only** sanctioned escape
from "types, never values" in schema diagnostics. It exists for *representation*
drift — the class of bug where the type name alone is ambiguous. `received:
"string"` does not tell you whether the string is a digit-string epoch, an
ISO-8601 date, or garbage, nor whether the magnitude is seconds or milliseconds.

To enroll a field, add one entry keyed `` `${schema} ${dottedPath}` `` with
a describer function.

**Review expectation.** Adding an entry is a privacy decision, and a reviewer
should require all of:

- **Exact-match key, both halves.** No prefixes, no wildcards, no globs.
  Enrolling `record.` would silently extend the exemption to `record.owner_email`,
  which nobody reviewed. The lookup is a plain string compare and must stay one.
- **Is this field's content non-sensitive for every tenant, always?** Not
  "usually", not "in practice".
- **Do the descriptors distinguish REPRESENTATIONS rather than values?** The
  describer returns a small fixed vocabulary of enum-like strings derived from
  shape (`typeof`, `Number.isInteger`, `/^[0-9]+$/`, a coarse magnitude bucket).
  It must never return the value, a substring of it, its length, or a bucket
  fine enough to reconstruct it. `describeEpochLike`'s three-way
  seconds/millis/micros verdict is the **granularity ceiling**, not a starting
  point — `unix_seconds` spans roughly 2001–5138 CE, so learning a timestamp is
  "seconds" narrows it by essentially nothing.
- **Could someone with Sentry read access learn anything about a person from the
  descriptor vocabulary alone?** If yes, do not enroll.
- **Is the describer total?** Any input — `undefined`, `null`, a function, a
  cyclic object — must yield a descriptor set rather than throw.

Enrollment has a second effect worth knowing: an enrolled row is retained
**unconditionally** by the truncation sort, ahead of declaration order. That is
deliberate — the reason a field is enrolled is that a human decided its failures
are the ones worth reading — but it means enrollment spends part of the 10-row
budget.

### Adding a resource ref

`resourceRefRegistry.ts` is the sibling registry, and it authorizes something
stronger: forwarding a value **verbatim**. Review expectation, all four:

- the field holds an opaque, keyed, one-way pseudonym in `DiagnosticsRef` shape
  — never an extid, display name, email, billing identifier, or slug. The shape
  check enforces the format; only review enforces that it is genuinely a
  pseudonym;
- the schema is an internal/admin surface, not customer-facing;
- aggregating by this ref answers an operational question the parameterized
  route cannot;
- cardinality is bounded by tenants, not by requests. A per-request id does not
  belong on an indexed dimension.

### Adding a scrubber

New nets go in `src/utils/diagnostics/scrubbers.ts`, and are composed inside
`scrubOpaqueIdentifiers` in the documented order (credentials before object ids;
IPv6 before IPv4; all of them after the email pass and before the 62/31-char
verifiable-id pass).

**Review expectation.** The design constraint is symmetric, and this is the part
reviewers get wrong:

- **Under-scrubbing** leaks a tenant, customer or credential reference into an
  indexed field.
- **Over-scrubbing is equally a defect.** These same functions run over stack
  frames, module paths, version strings and schema field names. A net that eats
  those degrades every event on the platform rather than one. `org_context`,
  `price_formatted`, `sub_total` and `subscription_period_end` are all real
  field names in this tree that a careless prefix net would destroy — and those
  field names are the diagnostic payload the whole subsystem exists to preserve.

So every net must be (a) anchored, (b) restricted to a known prefix or a known
literal shape, and (c) required to carry evidence of being machine-generated — a
digit, an uppercase character, or an exact length — before it fires.

Each net gets its **own sentinel**, whitespace-free and matching
`/^\[[A-Z_]+\]$/`. The later path patterns use a `[^/\s]+` value class and would
split a sentinel containing a space.

Two further requirements:

- **`EMAIL_PATTERN` is a mirror.** It is duplicated verbatim in
  `lib/onetime/initializers/setup_diagnostics.rb`, and the two must change in
  the same commit — a Sentry payload can be assembled by either half, so
  widening one still leaks. The only permitted difference is the flags.
- **The superset-of-the-validator invariant.** Whatever the email validator
  accepts is storable, so every redactor must be at least as wide as
  Truemail's pattern. The former ASCII-only class matched none of
  `josé@example.com`, `用户@example.com`, `user@пример.рф` — all storable — so
  they reached Sentry in the clear.

### Adding an API collection

Extending `PARAM_NAME_BY_COLLECTION` in `apiRouteContext.ts` is how an
id-bearing endpoint gets the **positional guarantee** (§7). Leaving it out does
not merely lose a nice parameter name — it drops that endpoint's children back
to the shape heuristic, which is best-effort.

`COLLECTION_CHILD_LITERALS` is machine-checked against the Ruby route table by
`collectionChildLiterals.spec.ts`; do not hand-edit it without running that
spec.

---

## 7. Known limitations

These are real. None of them is theoretical, and several were found by executing
the code rather than reading it.

**1. Route parameterization is a guarantee only under known collections.**
A segment whose *parent* is in `PARAM_NAME_BY_COLLECTION` is replaced by
position, whatever it looks like — that is fail-closed and it is what makes
`/api/colonel/users/alice` → `/api/colonel/users/:user_id`. Everywhere else,
`looksLikeIdentifier` is a heuristic. Verified: `/api/widgets/alice` is emitted
**unchanged**, because `widgets` is not a known collection and `alice` is short,
lowercase and digit-free. The control of last resort is `sanitizeApiRoute`'s
scrub pass, which nets emails and identifier shapes but not a bare slug.

**2. `issueCode` on a `custom` issue can carry an author-supplied value verbatim.**
`REFINEMENT_ID` bounds punctuation and `safeConstant` bounds anything the
scrubbers recognize, but no shape predicate distinguishes a rule name from a
tenant slug — `must-exceed-min` and `acme-corp-tenant` are the same lexical
class. Verified: `ctx.addIssue({ params: { id: 'acme-corp-tenant' } })` emits
`issueCode: "acme-corp-tenant"`. Nothing in `src/` supplies `params` today, so
this is currently unreachable; it is **author discipline**, not a control. Say
so in review of any new `ctx.addIssue` params.

**3. `redactionSignals` can carry a pre-existing bracketed token.**
`collectRedactionSignals` extracts `/\[[A-Z_]+\]/g` from the *scrubbed* message,
so if any net fired, an unrelated bracketed uppercase token already in the
message rides out with the sentinels. Verified: the message
`bad [FOO] for alice@example.com` yields `["[FOO]", "[EMAIL_REDACTED]"]`. The
token class is narrow (uppercase and underscore only), but it is
author-controlled text reaching an emitted field.

**4. Breadcrumb structural allowlisting covers three categories only.**
`xhr`, `fetch` and `navigation`. Every other category — `console`, `ui.click`,
`ui.input`, `history`, `sentry.*` — keeps its `data` bag structurally intact and
is covered only by the free-text pass (message scrubbing everywhere,
`data.arguments` dropped on console). A producer that writes a header bag onto a
`ui.click` breadcrumb is **not** refused. No such producer exists today; if one
appears it needs its own allowlist entry, not a wider reading of the existing
one.

**5. Console breadcrumbs are not fully removed in production.**
`minify.compress.dropConsole: true` removes the `console.*` calls the minifier
can resolve *statically* from the production bundle — which is one self-contained
chunk, so that covers bundled dependencies as well as our own code. What
survives is whatever it cannot resolve statically. In dev nothing is minified
and the surface is wide open, and a dev session pointed at a real DSN reaches
Sentry exactly like a production one.

**6. Some identifier shapes are preserved deliberately.**
A bare 32-hex run is byte-identical to a W3C/Sentry `trace_id` and a 40-hex run
is a git commit; both are ops-useful, neither is personal data, so `UUID_PATTERN`
requires the hyphens. Loopback, `0.0.0.0` and `255.255.255.255` survive the IP
net because they identify a machine role, not a person. Verified: a 32-hex trace
id and a 40-hex commit hash pass through unchanged, while `10.1.2.3` becomes
`[IP_REDACTED]`. The residual ambiguity in the other direction is a genuine
four-part dotted version string whose every component is 0–255 — indistinguishable
from an address by inspection, and resolved toward redaction.

**7. The backend scrubbers are narrower than the frontend's.**
`setup_diagnostics.rb`'s `scrub_text` applies sensitive paths, named query
params, `EMAIL_PATTERN` and `IDENTIFIER_TEXT_PATTERN` — and **not** the
credential, prefixed-object-id, extid, UUID or IP-literal nets the frontend
gained on this branch. A `sk_live_…` or `cus_…` interpolated into a *Ruby*
exception message is not netted by shape today. `EMAIL_PATTERN` itself is
mirrored and in sync; the opaque-identifier nets are not.

**8. Extras and tags are unscrubbed by construction.** Restated here because it
is the single most consequential thing on this page. `beforeSend` does not
filter `event.extra` or `event.tags`. Every producer that writes to either is
its own boundary.

**9. Transaction-event param scrubbing degrades when the user navigates away.**
An in-flight transaction whose `request.url` is gone, on a route whose
`event.transaction` no longer matches the current route, gets **no** layer-1
param values — only the always-on pattern nets apply. A short, meta-scrubbed
param on a non-sensitive path is unrecoverable at the value layer in that
window.

**10. The client cannot prove a ref is a keyed digest.**
It checks the key set (`strictObject`) and the content shape (16 lowercase hex),
and both are required — `{ actor_ref: "alice@example.com" }` is a *valid* block
by key set alone. What neither check can establish is that the 16 hex characters
came from the intended derivation. That trust is placed in the server, and
`ACTOR_REF_PATTERN` must change in the same commit as any change to
`DiagnosticsRef::REF_LENGTH`. It fails closed, so drift costs actor correlation
rather than leaking.

**11. Copying `ACCOUNT_ID_SECRET` between installs rebuilds cross-install
correlation** under a `deployment` label — a case code cannot enforce against.
That secret is generated per install and documented as un-shareable; sharing it
is a configuration error with consequences well beyond diagnostics.

---

## See also

- `src/utils/diagnostics/schemaIssueProjection.ts` — the projection, and why
  rows must stay flat
- `src/utils/diagnostics/safeFieldRegistry.ts` — the shape-descriptor allowlist
- `src/utils/diagnostics/resourceRefRegistry.ts` — the resource-pseudonym allowlist
- `src/plugins/core/enableDiagnostics.ts` — the client and the three handlers
- `src/tests/plugins/core/diagnostics/diagnosticsBoundary.spec.ts` — the
  end-to-end acceptance suite that enforces both the privacy floor and the
  diagnostic-power floor
- `lib/onetime/utils/diagnostics_ref.rb` — server-side derivation
- `lib/onetime/initializers/setup_diagnostics.rb` — the Ruby-side boundary
- `docs/adr/adr-022-secret-activity-network-capture-privacy.md` and
  `Onetime::Security::RequestContext` — the same posture applied to the network
  rather than the actor
