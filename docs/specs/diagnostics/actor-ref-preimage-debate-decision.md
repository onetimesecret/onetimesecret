# [DECISION] Actor ref pre-image: extid, not email

**Keywords:** Sentry user.id, DiagnosticsRef, actor_ref, pre-image, HMAC, extid, email hash, ACCOUNT_ID_SECRET, FEDERATION_SECRET, residency, PR #4250, pseudonymous diagnostics, erasure, enumeration, dictionary attack, capture_error scrubbing, organization_ref, actor_scope, re-key discontinuity, external_id, customer_id

**Date:** 2026-08-22 (rev 4, implementation-ready per reviewer) · **Branch:** `feat/diagnostics-signal-quality` (PR #4250)
**Status:** GO — rework PR #4250 from email pre-image (candidate A) to extid pre-image (candidate B).

## Decision

`DiagnosticsRef.actor_ref` derives from the customer **extid**, HMAC'd and truncated, keyed by **`ACCOUNT_ID_SECRET`**. `FEDERATION_SECRET` is dropped from diagnostics. The residency apparatus is deleted: extid pre-images are minted per-region, so separately provisioned regional customer records **do not correlate by default** (see Threat model for why not "structurally impossible").

Candidates C (stored federation email hash) and D (federation-keyed `actor_identifier`) rejected with prejudice — do not re-litigate. (Editorial note accepted: C's "buys nothing" was overstated; independent keying does alter compromise behavior. Its availability, join-key, browser-exposure, and lifecycle costs remain sufficient grounds.)

## Correlation subject (reframed per review)

The subject is the **customer record**, not the human. This makes B affirmatively better, not a privacy concession:

- Extid is stable across email change (`change_email` mutates email without replacing the record); email-derived refs split one account on email change.
- Email-derived refs conflate different people on address reassignment or delete-and-recreate; extid refs cannot.
- Consequence: "returning user after deletion counts as new" is correct behavior under this definition, not a price.

## Why B won (Round 5 values ordering)

A answered "maximize diagnostic correlation subject to no raw disclosure"; B answers "minimize identity involvement, accepting narrower diagnostics" — the operator's actual ordering. Decisive costs of A:

1. **Enumerability.** `HMAC(secret, email)` under key compromise → offline dictionary re-identification against cheap email lists.
2. **Erasure.** Email refs re-link a data subject across deletion + re-signup within retention.

## Threat model, stated precisely (review corrections #4, #5)

- Extids are **not** datastore-only: they appear in bootstrap payloads, authenticated serializers, API responses, logs. That is their job — extids are external identifiers, deterministically derived one-way from high-entropy objids. Not an authentication or integrity token; non-enumerable, not secret.
- Narrowed claim: B moves the attack from "leaked secret + public email list" (A) to "leaked secret + an auxiliary extid dataset" (B). Material improvement, not immunity.
- Cross-region: no cryptographic enforcement — a cloned datastore plus copied secret reporting to the same Sentry project reproduces refs. **Decision: accept this; no residency discriminator.** That scenario is operator self-misconfiguration, and a discriminator resurrects the apparatus B exists to delete.

## Keying — coupling to ACCOUNT_ID_SECRET accepted (operator decision)

The purpose prefix (`ACTOR_INFO` in the HMAC message) namespaces but does not enable independent rotation; refs are only as strong as `ACCOUNT_ID_SECRET`. **Decision: accept the coupling; no dedicated `DIAGNOSTICS_REF_SECRET`.** The extra secret would buy robustness in a compromise scenario whose marginal exposure is already small, at zero diagnostic gain. Rotating `ACCOUNT_ID_SECRET` rotates diagnostics refs; under 14-day Sentry retention the discontinuity ages out and is a non-event. Note this in module docs.

## Implementation requirements (regression traps)

1. **Scrub all extid aliases at the capture boundary.** `ErrorHandler.capture_error` currently removes only `email`/`cust`/`customer`; hooks pass extids raw into Sentry context today under multiple keys — `extid:` (account hooks, e.g. around `create_default_workspace`), `external_id:`, and extid-valued `customer_id:` (e.g. `update_password`). Under B the extid is the sensitive pre-image: consume and remove **`:extid`, `:external_id`, and known extid-valued `:customer_id`** before setting context — or first standardize callers on one explicit key, then scrub that.
2. **Kill the bare-string candidate API.** `diagnostics_actor` treats any string as email; leaving it would let existing `email:` callers silently hash emails under the new key. Require an explicit customer object or explicit `extid:`; reject generic string fallback.

## Coverage (review correction #7)

- B **improves** attribution for hooks already supplying `extid` that A ignores (verification, workspace provisioning, etc.), with no datastore read.
- Account deletion retains attribution: `account[:external_id]` is available pre-delete.
- Genuine losses: account creation before extid exists; email-only credential flows; datastore-outage rescues holding only an email. Events still captured and grouped by grouping rules + volume; **actor cardinality ("one account or many?") is unanswerable for this class** — that is the accepted price. True identity needs on the auth surface resolve at support time by asking the user.

## organization_ref and actor_scope — nothing to decide, one note to write

The org ref's pre-image is already the per-install org objid; **separately provisioned organization records do not correlate cross-install** (same clone exception as the threat model). Dropping `FEDERATION_SECRET` touches org refs only mechanically: installs deriving under `federated` scope re-key once to the deployment key. Existing org (and actor) ref values in Sentry stop matching new ones for up to 14 days, then the discontinuity ages out of retention. No semantics change, no privacy change. **Action: one-line PR note that refs re-key at deploy, so the discontinuity window isn't investigated as a bug.**

`actor_scope` collapses to constant `deployment`: drop it from the wire contract (TypeScript type, tags, tests, docs) or leave it as a constant — implementation-time taste call, whichever churns less.

Symmetry note: post-rework, actor and org refs both key on server-minted per-install identifiers; Round 1's "deliberate asymmetry" inverts into an argument for B.

## Scope of rework

`DiagnosticsRef`, `ErrorHandler.diagnostics_actor` + `capture_error` alias scrubbing, specs, module docs (rotation coupling, boundary-attribution loss noted so the trade was visibly bought), PR note on the re-key discontinuity. PR description leads with: no-cross-region-correlation-by-default replaces discipline-maintained residency mixing; net code shrinks.

## Principles carried forward

Purpose test (diagnostics, not analytics); disclosure-boundary parties (Stripe may know, Sentry must not); default non-correlation beats enforced invariants beats configuration; consistency binds cross-surface, not cross-time; pre-image entropy is a privacy property; erasure semantics are part of the design; values ordering is an input, not an output; the correlation subject is the record, not the human.

*Sources: uploaded debate brief "actorrefpreimagedebate.md"; external reviewer feedback rounds 1–2 with file/line citations (recorded as reviewer's claims, spot-verify in repo); operator decisions on keying coupling and org scope, session 2026-08-22. Reviewer declared rev 4 implementation-ready.*
