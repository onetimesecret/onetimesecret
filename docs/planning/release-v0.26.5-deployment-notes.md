# v0.26.5 — Deployment Notes block

Paste the block below into the GitHub release body. It highlights and links; the
detail lives in [`docs/operations/upgrading-v0-26-5.md`](../operations/upgrading-v0-26-5.md).

---

## Deployment Notes

> [!IMPORTANT]
> **Three gates now fail closed, and all three answer the same `404`.** The admin
> host gate, the admin CIDR gate, and the new per-domain sign-in/sign-up opt-ins
> reject as not-found, so the symptom gives you no clue which one fired. The boot
> log names each active gate — check it first. Full detail in the
> [Upgrading to v0.26.5](https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-26-5/) guide.
> - [ ] **Set `ADMIN_ALLOWED_HOSTS`** if you reach `/colonel` by anything other than
>       `HOST`/`DEFAULT_DOMAIN` or its `www.` sibling — an internal hostname, a
>       `LINK_DOMAINS` entry, a tenant domain. `*` disables the restriction. (#4062, #4127)
> - [ ] **Check every entry in `ADMIN_ALLOWED_CIDRS` parses** if the variable is set at
>       all. An allowlist with no usable range now denies both admin surfaces instead
>       of being ignored. Unset it if you did not mean to restrict by network. (#4062)
> - [ ] **Confirm the sign-in opt-in on each custom domain** that serves password or
>       magic-link sign-in. Full mode now enforces the ADR-024 default-OFF rule that
>       simple mode, the display surfaces and the settings API already applied.
>       (#4169, #4184)
> - [ ] **Enable `TRUSTED_PROXY_ENABLED=true`** if you sit behind a proxy — without it
>       `TRUSTED_PROXY_MODE`, `_CIDRS` and `_DEPTH` are inert, forwarded hosts stay
>       untrusted, and the admin host gate sees only the connecting host.

> [!WARNING]
> **`RABBITMQ_VERIFY_PEER` was failing open.** It was read as `== 'true'`, so `1`,
> `yes` or `TRUE` silently **disabled** TLS peer verification on a default-ON
> control. Those values now enable it, and an unrecognized value fails the boot.
> Confirm your value is `true` or `false`. If you were unknowingly relying on the
> old behaviour to reach a node with an untrusted certificate, that connection will
> now fail — set `RABBITMQ_VERIFY_PEER=false` explicitly and fix the certificate.

> [!WARNING]
> **`BILLING_ENABLED` and `STRIPE_AUTOMATIC_TAX` can turn themselves on.** Both moved
> to the same strict reader. `BILLING_ENABLED=1` (or `yes`, `on`, `TRUE`) was **off**
> in v0.26.4 and is **on** in v0.26.5. Set the literal `false` if that was the intent.
> A value outside `1/true/yes/on/y/t` / `0/false/no/off/n/f` now raises at boot.

**Also check before upgrading:**

- **`GEO_HEADER` is now filter-mode only.** Depth-mode and direct-connect installs
  need `GEO_DB_PATH` pointing at a MaxMind country `.mmdb`, or session country
  resolves to Unknown. A bad path fails at boot, not per request. (#4024, #4068)
- **Passkey variables renamed.** `WEBAUTHN_VERIFY_ACCOUNT` → `AUTH_WEBAUTHN_VERIFY_ACCOUNT`,
  `WEBAUTHN_AUTOFILL` → `AUTH_WEBAUTHN_AUTOFILL`. The old names are ignored and log a
  deprecation; they will not fail your boot. Only the literal `true` enables either.
- **The strict boolean vocabulary covers only three variables.** `BILLING_ENABLED`,
  `STRIPE_AUTOMATIC_TAX`, `RABBITMQ_VERIFY_PEER`. Every other flag is still a literal
  string comparison in the config template, and in two directions: flags written
  `== 'true'` need the literal `true`, while flags written `!= 'false'` need the
  literal `false` to switch off — so `API_ENABLED=no` leaves the API **on**. Use
  `true`/`false` everywhere and none of this applies to you.
- **Depth-mode workarounds should be undone.** If you inflated `TRUSTED_PROXY_DEPTH`
  to compensate for the old miscount, restore the real value. (#4024)
- **Org-trail geolocation is opt-in and stays off.** `SECRET_ACTIVITY_GEO_COUNTRY_ENABLED`
  defaults to `false` pending the legal review in ADR-021. (#3989)

**Background on the admin host gate:** it anchors on the canonical hostname, which
means it needs a routable one. On an install serving `localhost` or a bare IP, boot
logs `Admin host allowlist INACTIVE: no routable hostname configured` and **no host
gate applies at all**. That is deliberate — the alternative locks such installs out
of their own admin console — but it makes "the gate is now active" conditional on
`site.host` being a real hostname. Set `ADMIN_ALLOWED_HOSTS` explicitly if you want
the gate on a bare-IP install.

**Rollback:** no schema migration and no bulk data transform in this release, so
rolling back is pinning the previous tag and restarting. Config written for v0.26.5
is inert on v0.26.4 — the new variables are simply unread — with one exception: the
three strict-parsed booleans revert to `== 'true'`, so `BILLING_ENABLED=yes` becomes
off again on the old tag.
