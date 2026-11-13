# Domain identifier naming: `domainid`, `domain_id` and `objid`

Status: Draft — 2026-10-22. Written 2026-09-01 as a ticket draft; not filed.
Re-verified against `main` on 2026-10-22: nothing proposed here is implemented.
Line numbers are from that date.

## Summary

`CustomDomain` and its seven per-domain config models disagree on what the
domain identifier is called, and the disagreement is invisible until a call
fails at runtime. Reading the id requires `domainid` (no underscore); passing
it to any config model requires `domain_id:` (with underscore). Neither name
matches the `objid` that every other Horreum model in the codebase uses as its
identifier.

This is a papercut with teeth: `SigninConfig.create!(domainid: id, ...)` does
not raise a `NoMethodError` or an `ArgumentError`. `domainid:` is swallowed by
`**attrs` and the guard then reports `"domain_id is required"`, which points
the reader at the value rather than at the key. Same shape for `SsoConfig`.

## Evidence

Read side. `CustomDomain` is the only model in `lib/onetime/models/` whose
`identifier_field` names a derived method rather than a stored field:

- `lib/onetime/models/custom_domain.rb:99`: `identifier_field :domainid`
- `lib/onetime/models/custom_domain.rb:242`: `def domainid; objid; end`
  (comment: "Alias domainid to objid for API compatibility")

Every sibling (`secret.rb`, `customer.rb`, `receipt.rb`, `organization.rb`,
`organization_membership.rb`) uses `objid` directly.

Write side. All seven config models key on an underscored stored field:

- `custom_domain/signin_config.rb:229-230`, `sso_config.rb:124-125`,
  `api_config.rb:32-33`, `homepage_config.rb:108-109`,
  `signup_config.rb:108-109`, `mailer_config.rb:52-53`,
  `incoming_config.rb:48-49`
- Their finders and creators are `find_by_domain_id(id)` and
  `create!(domain_id:, **attrs)` (`signin_config.rb:528` and `:1264`,
  `sso_config.rb:647` and `:838`).

So a correct console call has to switch spelling mid-expression:

```ruby
d = Onetime::CustomDomain.from_display_domain('secrets.example.com')
Onetime::CustomDomain::SigninConfig.create!(domain_id: d.domainid, enabled: true)
#                                           ^^^^^^^^^          ^^^^^^^^
```

Counts in `lib/`: 39 occurrences of `domainid`, 667 of `domain_id`.

Related third spelling: `CustomDomain#custid` (`custom_domain.rb:236`) also
returns `objid`, the domain's own id under a customer name, left over from when
domains were customer-scoped rather than org-scoped (`field :org_id` comment at
`custom_domain.rb:102`).

The frontend has settled on one name and pinned it:
`src/tests/contracts/custom-domain-safe-dump-fields.ts:13` lists `domainid`,
and `custom-domain-schema-contract.spec.ts:20-23` documents that `identifier`
duplicates `domainid` and that the frontend uses `domainid` exclusively. Any
rename has to treat the `safe_dump` payload as a separate, versioned decision.

## Why it is not just cosmetic

1. Silent keyword drop. `create!(domain_id:, **attrs)` means a misspelled key is
   not an error at the call site; it becomes an unrelated-sounding failure.
2. The class-level docblock is already the workaround. `custom_domain.rb:44`
   has to explain that `domain_id` (with underscore) is the foreign-key field
   that stores the objid value. Documentation compensating for a naming split
   is the tell.
3. It costs incident time. This tripped up the v0.26.2 SSO console recovery on
   2026-07-31, where the grandfathering snippet had to be corrected twice: once
   for `domainid` vs `domain_id`, once for `instances.each` yielding
   identifiers rather than records.

## Proposed direction

Three tiers, cheapest first. Do 1 and 2 now and defer 3.

1. Make the wrong key loud (small, no migration). In each config model's
   `create!`, reject unknown keys instead of ignoring them:

   ```ruby
   unknown = attrs.keys - PERMITTED_CREATE_ATTRS
   raise Onetime::Problem, "unknown attribute(s): #{unknown.join(', ')}" if unknown.any?
   ```

   Add `domainid:` to a small alias map that raises with the correct spelling
   named explicitly. This removes the actual failure mode without touching any
   stored data.

2. Add a read-side alias and standardize the docs (small). Give `CustomDomain`
   a `domain_id` reader alongside `domainid` so `d.domain_id` works and the two
   spellings stop being a trap in the direction people actually hit. Keep
   `domainid` as the `identifier_field` and the `safe_dump` key; the frontend
   contract depends on it. Note the alias in the identifier docblock in
   `custom_domain.rb` and in `config_registry.rb`.

3. (Deferred) Converge on `objid`. `identifier_field :objid` for
   `CustomDomain`, with `domainid` kept as a deprecated alias, would make it
   consistent with the other models. This touches the `safe_dump` payload and
   the frontend contract specs, so it needs its own issue, a payload-compat
   window (emit both keys), and a deprecation of `#custid` on `CustomDomain` at
   the same time.

## Scope and non-goals

- No datastore migration. The stored field names do not change in tiers 1 and 2.
- No API payload change. `domainid` stays in `safe_dump`.
- `Receipt#domain_id` (`receipt.rb:53`) is a genuine FK to a CustomDomain objid
  and is already correctly named. Leave it.

## Acceptance

- [ ] Passing `domainid:` to any config model's `create!` raises an error that
      names `domain_id` as the correct key
- [ ] `CustomDomain#domain_id` reads the same value as `#domainid`
- [ ] Unknown attributes to `create!` raise instead of being silently dropped
- [ ] Identifier docblock in `custom_domain.rb` states the read and write
      spellings side by side, with the console example
- [ ] Existing custom-domain contract specs still pass unchanged
