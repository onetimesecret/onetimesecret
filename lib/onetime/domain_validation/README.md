# Domain Validation Module

Custom domain SSL and DNS validation strategies.

## Strategies

| Strategy          | Ownership check                                                      | SSL Certs | DNS Widget | Use Case                 |
| ----------------- | -------------------------------------------------------------------- | --------- | ---------- | ------------------------ |
| `approximated`    | TXT record, via the Approximated API with our own lookup as fallback | Managed   | Yes        | Approximated.app service |
| `caddy_on_demand` | TXT record, via our own lookup                                       | Auto      | No         | Caddy on-demand TLS      |
| `passthrough`     | None                                                                 | External  | No         | Manual/external certs    |

## Ownership check

`validate_ownership` has three outcomes (see `base_strategy.rb`):

| `validated`                     | Meaning                                                                                                                   | Effect on the stored `verified` flag             |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `true`                          | Exactly one TXT value at the domain's validation record, equal to the challenge                                           | Set to true                                      |
| `false`                         | The resolver stated the record is missing (NXDOMAIN, or NOERROR without TXT data) or the values are not exactly one match | Set to false, unless a Colonel override holds it |
| `nil` (+ `indeterminate: true`) | No answer: SERVFAIL, REFUSED, timeout, network error, a hostname with no A-label form                                     | Left unchanged, for at most 7 days (see below)   |

`TxtVerifier` implements this with `TxtResolver`, a small resolver that reads the DNS response code. `Resolv::DNS#getresources` cannot be used for it: it returns `[]` for NXDOMAIN, SERVFAIL and a timeout alike.

A reply only counts as definitive when it is an answer about the name (`DnsStubResolver#ensure_usable!`). A NOERROR or NXDOMAIN reply with neither `ra` nor `aa` set (a nameserver that does not recurse for us, typically an upward referral) and an answer section with nothing owned by the queried name are skipped like a failed exchange, so they end up indeterminate rather than "not found". CNAME chains are followed whatever order the answer section lists them in.

Internationalised hostnames are queried, and probed, in their A-label form (`AsciiHostname`). `CustomDomain` stores the hostname as typed; sent as typed it would come back NXDOMAIN, which is our encoding speaking and not the customer's DNS.

The reverse direction is handled in the `CustomDomain` lookup. Names that arrive over the wire are A-labels: the SNI name Caddy passes to the ACME ask endpoint, and the Host header. `CustomDomain.display_domain_id_for` (behind `load_by_display_domain`, `from_display_domain` and `resolve_domain_id`) tries the name as given, then its A-label form, then its Unicode (NFC) form, so a domain stored as `bücher.example` is found when asked for as `xn--bcher-kva.example` and the other way round. Stored data is not rewritten, a plain ASCII name still costs one index read, and a name that cannot be converted is a miss (403 from the ask endpoint), not an error. The same lookup keeps the second form of an already registered name from being registered as a separate domain.

Under `caddy_on_demand` the TXT check is the ownership proof. Caddy completing an ACME challenge shows that the name resolves to this deployment; it does not show which account, if any, controls the domain. The internal ACME endpoint (`apps/internal/acme`) only authorises a certificate for a domain that is `ready?`, which requires `verified`.

`caddy_on_demand` makes one exception to "nil leaves `verified` unchanged": a domain that is verified with no `verified_confirmed_at`. The hold exists to protect a verification a TXT check once established, and `verified_confirmed_at` is the record of that check; without one there is nothing on record for the hold to protect, and with the status probe now filling in `resolving`, holding the flag would make the domain `ready?`. The strategy returns `false` for it instead of `nil`. A Colonel override holds the domain as for any other `false`, and the next check that finds the record verifies it.

Three kinds of domain are verified with no `verified_confirmed_at`:

- Verified by `caddy_on_demand` before it checked TXT records. No proof exists.
- Verified by `passthrough`, which passes every domain without a lookup. `VerifyDomain` records a confirmation only for a strategy whose `proves_ownership?` is true (`approximated`, `caddy_on_demand`), so a passthrough pass never writes the field. No proof exists.
- Verified by `approximated` on a version that did not have the field yet. The proof was real and is simply not on record. The field is written by the first passing check on this version.

The third kind matters for a cutover from `approximated` to `caddy_on_demand`. Cutover is also the first time the app needs its own working resolver for every check; with no nameserver in `resolv.conf` or DNS egress blocked, every lookup is indeterminate. Before switching strategy, upgrade while still on `approximated`, run a full `bin/ots domains verify --all` pass (or let `DomainRefreshJob` walk every page) so that `verified_confirmed_at` is recorded for each proven domain, and confirm the app host can resolve names. Otherwise an unanswered first lookup under `caddy_on_demand` withdraws `verified` from a domain Approximated had proven, until the next passing check or a Colonel override.

Existing domains are only re-checked when something runs the check. Installs that do not run the scheduler with `jobs.domain_refresh` enabled (both are off by default) must run `bin/ots domains verify --all` once after upgrading for the TXT check to take effect on existing domains, and periodically after that.

Under `approximated` the API's answer is used when it has one. When it has none, `TxtVerifier` decides instead, with the same three outcomes. "None" covers a 200 whose own DNS lookup failed (`actual_values: false`) and every case where the checker could not be asked: no API key configured, a non-200 response, a client exception. None of those is evidence about the customer's DNS, so none is reported as a failed check. A deployment whose API key is missing or revoked therefore keeps confirming its domains through the native lookup, and only a domain whose native lookup is indeterminate as well runs into the confirmation window below. An exception raised by a strategy is handled the same way in `VerifyDomain`: indeterminate, never failed.

### Confirmation window

An indeterminate check may not hold `verified` indefinitely. `VerifyDomain::ConfirmationWindow` (`lib/onetime/operations/verify_domain/confirmation_window.rb`) keeps two timestamps on `CustomDomain`:

- `verified_confirmed_at`: the last passing TXT check. Not written for a pass from a strategy that does not check the record (`passthrough`).
- `verified_unconfirmed_since`: the first indeterminate check of a verified domain since then. A definitive outcome clears it when stored. While an explicit override holds, the timestamp is retained and the domain is exempt from expiry.

When a check is indeterminate and `verified_unconfirmed_since` is more than 7 days old (`ConfirmationWindow::MAX_AGE`), `verified` is withdrawn. The result reports `dns_outcome: confirmation_expired`, bulk results count it in `confirmation_expired_count`, and VerifyDomain logs a warning.

The window runs from the first indeterminate check, not from the last passing one. A deployment that does not run `DomainRefreshJob` may check a domain once in months, and one resolver failure on that check must not demote it. A demotion always takes two indeterminate checks at least 7 days apart with no passing check between them.

- A domain with no clock, which is every domain at upgrade, starts one on its first indeterminate check and is not demoted by that check (except under `caddy_on_demand` when it was never confirmed, see above).
- A Colonel override exempts the domain, as it does for a definitive failure.
- Unverified domains are not affected.
- A demoted domain becomes verified again on its next passing check.

## Bulk pacing

`bulk_rate_limit` is the pause, in seconds, a bulk run takes between domains. `approximated` declares 0.5 for its API rate cap; the other strategies declare none. `VerifyDomain` uses it for bulk runs unless the caller passes `rate_limit:` (the `jobs.domain_refresh.rate_limit` setting, or `bin/ots domains verify --all --rate-limit N`), which overrides the strategy, including with 0.

## Status check

`check_status` reports two things, each with the same three outcomes (`true`, `false`, `nil` = could not tell). `nil` never changes stored state.

|                | Stored in                         | `approximated`                                             | `caddy_on_demand`     | `passthrough`                  |
| -------------- | --------------------------------- | ---------------------------------------------------------- | --------------------- | ------------------------------ |
| `is_resolving` | `CustomDomain#resolving`          | Approximated's claim (`nil` while its status is `UNKNOWN`) | Our own A/AAAA lookup | Always `true`                  |
| `has_ssl`      | inside the `vhost` blob (`:data`) | Approximated's claim                                       | Our own TLS handshake | Always `true` (nothing stored) |

Caddy has no per-domain status API, so `caddy_on_demand` uses `TlsProbe`:

1. `AddressResolver` looks up A and AAAA and reads the response code. An address means `is_resolving: true`; NXDOMAIN or an empty NOERROR from both families means `false` (and `has_ssl: false`); SERVFAIL, REFUSED or a timeout means `nil` for both.
2. The addresses go through the shared egress guard (`Onetime::Http::Guard.validate_addresses!`). The hostname is customer-controlled, so if any address is loopback, private, link-local or otherwise reserved, nothing is dialled: `is_resolving: true`, `has_ssl: nil`.
3. The probe connects to a vetted IP on port 443 (never re-resolving the name), sends the hostname as SNI, completes a handshake with chain and hostname verification, and closes. No application data is sent. A verified handshake is `has_ssl: true`. A TLS error, an untrusted or mismatched certificate, or a refused or dropped connection is `false`. A timeout or an unroutable address is `nil`.

`resolving` only means the name has an address record. It does not wait for a certificate, because the ACME ask endpoint requires `resolving` before Caddy may obtain one. It also does not check that the address is this deployment's; the certificate check is what shows that.

How the result is stored (`VerifyDomain#persist_changes`):

- `is_resolving` `true`/`false` is written to `resolving`; `nil` is skipped.
- `has_ssl` exists only inside the `vhost` blob. The strategy rewrites the blob whenever `is_resolving` is known, so its `status` and `is_resolving` follow the `resolving` field. When `has_ssl` is unknown, stored SSL fields are carried only from a blob this strategy owns and only while the stored `ssl_active_until` is in the future. At or after expiry (or when the date cannot be read), those fields are omitted: the blob makes no certificate claim and reports `PENDING_SSL` until a probe sees the current certificate. Approximated-era status is replaced instead of presented as a current probe result. The blob uses the keys the domain pages already read (`status`, `status_message`, `has_ssl`, `is_resolving`, `dns_pointed_at`, `ssl_active_from`, `ssl_active_until`, `last_monitored_unix`) plus `source: tls_probe`. `status` is `ACTIVE_SSL`, `PENDING_SSL` (resolves, no valid certificate yet) or `DNS_INCORRECT` (does not resolve).
- When the probe could not tell anything, the strategy returns neither `:data` nor `:mode`. Nothing stored changes and `vhost_fetch_failed_at` is set, which the UI shows as a failed check.
- After an `approximated` cutover, a known probe result replaces the stale UI-facing blob. The replacement carries `approximated_vhost_pending_cleanup: true`, preserving the cleanup obligation without presenting old Approximated status as current Caddy status.

Time budget per domain: address lookup 3s, connect plus handshake 5s, each spent only on a timeout. `DomainRefreshJob` runs the TXT check and this probe for every domain on its page; the job's header comment works out the per-page ceiling.

A certificate from a private CA (for example Caddy's `tls internal`) fails verification against the system trust store and is reported as `has_ssl: false`.

## Configuration

Configure in `config.yaml`:

```yaml
features:
  domains:
    validation_strategy: approximated # or passthrough, caddy_on_demand
    approximated:
      api_key: xxx
      proxy_ip: 1.2.3.4
      proxy_host: proxy.example.com
      proxy_name: Production Proxy
      vhost_target: target.example.com
```

## Moving off `approximated`

Changing `validation_strategy` away from `approximated` does not delete anything on Approximated. Each domain provisioned before the change keeps its remote vhost there (billable, and able to serve the hostname for as long as DNS points at the cluster). Under `caddy_on_demand`, the next known probe result replaces the old UI-facing `vhost` JSON with current status and a cleanup marker. The `remove_orphaned_approximated_vhosts` housekeeping chore uses either the old blob or that marker to clean up the remote vhost and local state.

Keep `approximated.api_key` and `proxy_ip` / `proxy_host` configured after the cutover. The chore needs the key to delete and the proxy address to tell which domains still point at the cluster. The chore reads `proxy_ip` as one or more entries separated by commas or spaces, each a single address or a CIDR range such as `203.0.113.0/24`. The same value is shown to customers as the A record target in the domain setup screens, so only widen it once no domain is still being set up against Approximated.

```bash
# Dry run (default): lists deletion candidates, makes no Approximated API call
bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

# Delete
APPROXIMATED_VHOST_CLEANUP=apply bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts
```

A vhost is deleted only when the domain resolves, from this host, to addresses outside the Approximated cluster, and Approximated itself reports the vhost as not resolving and not receiving traffic. A domain that still points at the cluster, has no DNS answer, or is served through another proxy (`ACTIVE_SSL_PROXIED`) is skipped and picked up again on the next run. The nightly HousekeepingJob runs the chore as a dry run unless the variable is set in its environment. `verified`, `resolving` and the TXT fields are never changed.

Under `caddy_on_demand`, a known status probe replaces old Approximated UI data immediately and retains `approximated_vhost_pending_cleanup: true`. The chore processes probe blobs with that marker and ignores ordinary probe blobs that only have `source: tls_probe`.

Re-run until the dry run reports no candidates. Domains that are skipped every time (no DNS answer, proxied, renamed, or a stored `vhost` value that is not valid JSON, which is logged as a warning) need a manual decision in the Approximated dashboard.

## Files

- `features.rb` - Config accessor (strategy, API keys, proxy settings)
- `strategy.rb` - Factory for creating strategy instances
- `base_strategy.rb` - Interface definition
- `approximated_strategy.rb` - Approximated.app implementation
- `approximated_client.rb` - HTTP client for Approximated API
- `passthrough_strategy.rb` - No-op for external cert management
- `caddy_on_demand_strategy.rb` - TXT ownership check and probe-based status; certificates delegated to Caddy
- `txt_verifier.rb` - TXT ownership check with three outcomes (shared by the strategies above)
- `txt_resolver.rb` - TXT lookup that reports the DNS response code
- `address_resolver.rb` - A/AAAA lookup that reports the DNS response code
- `dns_stub_resolver.rb` - Transport and time budget shared by the two resolvers
- `ascii_hostname.rb` - A-label (punycode) form of a hostname for DNS and TLS
- `tls_probe.rb` - Resolution and certificate check for `caddy_on_demand` status, behind the egress guard

## DNS Widget Integration

The Approximated strategy supports a DNS widget that auto-detects DNS providers and provides step-by-step instructions or automated updates.

**Backend**: `strategy.get_dns_widget_token` returns a token for the widget.

**Frontend**: Widget assets are self-hosted in `src/assets/approximated/`:

- `dnswidget.v1.js`
- `dnswidget.v1.css`

The widget renders only when `validation_strategy === 'approximated'` (see `DomainVerify.vue`).

## Usage

```ruby
strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)

# Core operations
strategy.validate_ownership(custom_domain) # DNS TXT validation (approximated, caddy_on_demand)
strategy.request_certificate(custom_domain) # SSL provisioning
strategy.check_status(custom_domain) # Current status

# Management (Approximated only)
strategy.delete_vhost(custom_domain) # Remove from provider
strategy.get_dns_widget_token # Token for DNS widget

# Capability checks
strategy.supports_dns_widget? # => true for approximated
strategy.manages_certificates? # => true for approximated
```
