# AZ5 — Organization extid uses plain SHA-256, not a keyed HMAC

- **Severity:** Medium — **NEEDS-VALIDATION** (defense-in-depth; compounded by AZ2 leaking objid)
- **Status:** Proposed fix
- **Affects default config?** Yes (every org has an extid; no `secret:` is configured)
- **Related:** finding 02 F5; AZ2 (objid leak removes the "objid is secret" assumption);
  the verifiable-id approach used for secrets (F12)
- **Primary files:** `lib/onetime/models/organization.rb:46` (`feature :external_identifier`),
  `familia/lib/familia/features/external_identifier.rb:300-346` (derivation),
  `familia/lib/familia/verifiable_identifier.rb:45-94` (the keyed-secret pattern to mirror)

## Problem (recap)

The Organization extid is declared without a `secret:` option:

```ruby
# lib/onetime/models/organization.rb:46
feature :external_identifier, format: 'on%<id>s'
```

In Familia's derivation, the absence of a configured `secret:` selects the **plain SHA-256** branch:

```ruby
# familia/lib/familia/features/external_identifier.rb:323-336
secret = options[:secret]
secret = secret.call if secret.respond_to?(:call)
random_bytes =
  if secret && !secret.to_s.empty?
    OpenSSL::HMAC.digest('SHA256', secret.to_s, normalized_hex)[0, 16]   # keyed: unforgeable
  else
    Digest::SHA256.digest(normalized_hex)[0, 16]                          # OTS today: derivable
  end
```

So `extid = format('on%<id>s', base36(SHA256(objid)[0,16]))` — a **deterministic, unkeyed** function of the
objid. Anyone who learns an org's `objid` can recompute its `extid` offline with no secret. Familia's own
comment flags exactly this: "Without a secret, a plain SHA-256 still removes the MT weakness and the 64-bit
truncation" (`external_identifier.rb:319-322`) — i.e. it is *better than the old MT seed*, but it is **not
unforgeable**.

This is normally low-impact because objids are internal. But **AZ2 leaks `objid`/`identifier` in the org
safe_dump** (`organization/features/safe_dump_fields.rb:17-18`), so the precondition is satisfied today: a
member who reads the org sees the objid and can derive the extid for *other* orgs whose objids leak (logs,
error messages, cross-references). The two findings compound.

*Confirm first:* whether the deployment can tolerate **extid rotation**. Switching from SHA-256 to HMAC
changes the derived extid for every existing org, which breaks already-issued extid URLs and the
`extid_lookup` index unless migrated (see migration below). Validate the operational appetite before
choosing eager vs. lazy rotation.

## Root cause

The extid was set up for *opacity* (non-sequential, non-enumerable) but not *unforgeability*. The design
assumes the objid stays secret, but provides no keyed binding so that, even if the objid leaks, the public
id cannot be reproduced. Secrets already use the stronger model — `Familia::VerifiableIdentifier` requires
`VERIFIABLE_ID_HMAC_SECRET` and **refuses a committed default** (`verifiable_identifier.rb:45-53`) — but the
organization extid was never brought up to that bar.

## Prescribed resolution

Configure a keyed HMAC `secret:` for the Organization `external_identifier`, sourced from an environment
variable with no committed default, mirroring the secrets `VERIFIABLE_ID_HMAC_SECRET` discipline. Use a
callable so the model still loads when the env var is absent (CI/tooling) and fails loudly only at first
derivation.

### Implementation steps

1. Add a keyed secret to the feature declaration, resolved lazily:

   ```ruby
   # lib/onetime/models/organization.rb:46
   feature :external_identifier,
     format: 'on%<id>s',
     secret: -> { ENV.fetch('EXTID_HMAC_SECRET') }   # no committed default; raises if unset
   ```

   The callable form is explicitly supported (`external_identifier.rb:324-330`): "Allow a callable secret
   ... so the value resolves lazily at first derivation ... a missing secret still raises loudly here — where
   it matters." This matches the fail-closed posture of `VerifiableIdentifier.secret_key`
   (`verifiable_identifier.rb:46-53`).

2. **Operations:** generate and set `EXTID_HMAC_SECRET` (`openssl rand -hex 32`) in every environment that
   creates or resolves org extids. Document it alongside `VERIFIABLE_ID_HMAC_SECRET`. Consider a single
   shared key vs. a distinct one per id-domain; distinct keys are cleaner (compromise of one does not affect
   the other) but require managing two secrets.

3. **Migration (the load-bearing part).** Existing orgs have SHA-256-derived extids stored in the
   `extid_lookup` index. Turning on HMAC changes the derivation, so choose a strategy:
   - **Recommended — persist extid, stop re-deriving:** if extid is stored on the record and looked up via
     `extid_lookup`, the new `secret:` only affects *newly minted* extids; existing orgs keep their stored
     extid and resolve unchanged. *Confirm first* that derivation runs once at create and the value is
     persisted (not recomputed on every access) — read `external_identifier.rb` around the `extid`
     accessor/`extid_lookup` to verify, because the answer dictates whether old URLs survive.
   - **Eager rotation:** a one-time housekeeping chore recomputes the HMAC extid for every org, rewrites
     `extid_lookup`, and (optionally) keeps the old extid as an alias for a deprecation window so existing
     URLs keep resolving. Heavier; only needed if extids are recomputed-on-read.

4. **Apply the same fix to AZ2 in tandem:** removing `objid`/`identifier` from the org safe_dump (AZ2) closes
   the *practical* derivation chain even before the key rotates, so land AZ2 first — it is the cheap, no-key
   mitigation — and add the HMAC as the durable defense-in-depth layer.

### Alternatives considered

- **Rely on AZ2 alone (hide the objid):** necessary but insufficient — objids leak through logs, support
  tools, and cross-model references. The keyed extid means an objid leak no longer yields the public id.
- **Reuse `Familia::VerifiableIdentifier` for orgs:** that mints *random* 256-bit ids with an embedded tag,
  not a *deterministic* function of objid. Org extids must stay deterministic (same objid → same extid for
  `extid_lookup`), so the keyed-HMAC branch of `external_identifier` is the right primitive — it keeps
  determinism while adding the key. Adopt VerifiableIdentifier's *secret-management discipline*, not its id
  shape.

## Test / verification

1. **Keyed derivation:** with `EXTID_HMAC_SECRET` set, two different secrets produce different extids for the
   same objid; the same secret is stable across runs (determinism preserved for lookup).
2. **Fail-closed:** with the env var unset, the first extid derivation raises `KeyError` (loud), and the
   model file still *loads* (callable defers the fetch) — assert both.
3. **Non-derivability:** given only an objid and no secret, the SHA-256 formula no longer reproduces the
   stored extid.
4. **Migration regression:** existing seeded orgs still resolve via `find_by_extid` after the change (proves
   the chosen migration strategy preserves old URLs).

## Effort & risk

- **Effort:** Low to add the `secret:`; Medium overall because of secret provisioning + the
  migration/rotation decision.
- **Back-compat:** **highest-risk item in the set** — if extids are recomputed on read rather than persisted,
  turning on the key silently changes every org's public id and breaks existing URLs and the lookup index.
  Resolve the "persisted vs. recomputed" question (step 3, *Confirm first*) **before** enabling in any
  environment with existing data.
- **Risk:** Low for new deployments; Medium–High for migration of existing data — gate behind the
  verification above.
