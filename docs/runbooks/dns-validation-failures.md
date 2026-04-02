# DNS Validation Failures Runbook

## Overview

The DNS validation system verifies that customers have correctly configured DNS records for sender domain authentication (DKIM, SPF, etc.). Provider-specific strategies (SES, SendGrid, SMTP) generate required records and verify them via live DNS lookups.

Key components:
- `Onetime::Operations::ValidateSenderDomain` - orchestrates verification flow
- `Onetime::DomainValidation::SenderStrategies::BaseStrategy` - DNS lookup, caching, retry logic
- `Onetime::Security::DnsRateLimiter` - prevents excessive verification attempts

## Error Types

| Error Type | Exception | Meaning | Retriable |
|------------|-----------|---------|-----------|
| timeout | `Resolv::ResolvTimeout` | DNS server did not respond in time | Yes (2 retries) |
| not_found | `Resolv::ResolvError` | NXDOMAIN - record does not exist | No |
| network_error | `StandardError` | Connection or network issues | No |
| rate_limited | `Onetime::LimitExceeded` | Too many verification attempts | No (wait for reset) |

## Retry Behavior

DNS timeouts trigger automatic retries with exponential backoff:

| Parameter | Value | Source Constant |
|-----------|-------|-----------------|
| Max retries | 2 (3 total attempts) | `DNS_RETRY_MAX` |
| Base delay | 0.5 seconds | `DNS_RETRY_BASE_DELAY` |
| Backoff | Exponential with 30% jitter | `RetryHelper` |
| Retriable errors | `Resolv::ResolvTimeout` only | `DNS_RETRIABLE` |

Only timeouts trigger retries. NXDOMAIN responses (`Resolv::ResolvError`) are authoritative and do not retry.

## Rate Limiting

Prevents abuse and excessive DNS queries per domain:

| Parameter | Value | Source Constant |
|-----------|-------|-----------------|
| Limit | 10 verifications | `MAX_VERIFICATIONS` |
| Window | 1 hour (3600 seconds) | `RATE_WINDOW` |
| Redis key pattern | `dns:ratelimit:{domain_id}` | `dns_rate_limit_key` |
| Auto-reset | After window expires | Redis TTL |

Rate limit enforcement is atomic via Lua script to prevent race conditions.

## Caching

DNS lookup results are cached to reduce query load:

| Parameter | Value | Source Constant |
|-----------|-------|-----------------|
| TTL | 10 minutes (600 seconds) | `DNS_CACHE_TTL` |
| Redis key pattern | `dns:cache:{hostname}:{type}` | `dns_cache_key` |
| Negative caching | Yes (empty results cached) | Prevents repeated lookups |
| Bulk operations | Redis pipelining | `fetch_cache_bulk`, `store_cache_bulk` |

## Troubleshooting

### Timeout Errors

Symptoms: DNS lookups fail with `Resolv::ResolvTimeout` after retries.

1. Check DNS resolver connectivity from the application server
2. Verify network/firewall rules allow outbound UDP/53 and TCP/53
3. Test manual resolution: `dig +short TXT _domainkey.example.com`
4. Check if upstream DNS provider is experiencing issues
5. Wait for automatic retry (exponential backoff handles transient issues)

### Not Found (NXDOMAIN)

Symptoms: Records show `verified: false` with empty `actual` array.

1. Verify DNS records exist at the customer's DNS provider
2. Check propagation time (can take up to 48 hours for some providers)
3. Confirm the hostname is correct (check for typos, missing subdomains)
4. Use `bypass_cache: true` after customer adds records to force fresh lookup
5. Test with external tools: `dig +short TXT hostname` or [dnschecker.org](https://dnschecker.org)

### Rate Limit Exceeded

Symptoms: `Onetime::LimitExceeded` raised, `verification_status: "rate_limited"`.

1. Check current status and reset time via `dns_rate_limit_status`
2. Inform customer of remaining wait time (`reset_in` seconds)
3. If urgent, manually clear the rate limit (see below)
4. Investigate if automated systems are triggering excessive verifications

### SPF Record Mismatch

Symptoms: SPF record shows as not verified despite customer adding it.

The system extracts the `include:` directive from the expected SPF record and checks if it appears in any actual SPF record. Customers can combine multiple provider includes in one record.

1. Verify the actual TXT record starts with `v=spf1`
2. Confirm the required `include:` directive is present
3. Check for typos in the include domain

## Manual Operations

### Check Rate Limit Status

```ruby
include Onetime::Security::DnsRateLimiter

status = dns_rate_limit_status('domain_id')
# => { remaining: 8, reset_in: 2400, current: 2, limit: 10 }
```

### Clear Rate Limit

```ruby
include Onetime::Security::DnsRateLimiter

clear_dns_rate_limit!('domain_id')
```

### Clear DNS Cache for a Record

```ruby
# Direct Redis deletion
redis = Onetime::CustomDomain.dbclient
redis.del('dns:cache:_dmarc.example.com:txt')
```

### Force Fresh Verification (Bypass Cache)

```ruby
result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: config,
  bypass_cache: true
).call
```

### Dry-Run Verification (No Persistence)

```ruby
result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: config,
  persist: false
).call
```

### Query Required Records Without Verification

```ruby
records = Onetime::Operations::ValidateSenderDomain.required_records(
  mailer_config: config
)
# => [{type: "TXT", host: "_dmarc.example.com", value: "...", purpose: "DMARC"}, ...]
```

## Monitoring

### Key Log Patterns

Search structured logs for these events:

| Pattern | Meaning |
|---------|---------|
| `DNS verification rate limited` | Rate limit hit, includes `retry_after` |
| `TXT lookup timed out` | DNS timeout after all retries |
| `TXT lookup failed` | NXDOMAIN or authoritative not found |
| `verify_all_records completed` | Success, includes `duration_ms` |
| `Sender domain validation complete` | Operation finished, includes `status` |
| `Domain ... approaching limit` | 2 or fewer attempts remaining |

### Metrics to Track

- DNS timeout rate (target: < 5%)
- Rate limit hits per hour (investigate if > 10/hour globally)
- Verification failure rate (baseline varies by customer base)
- DNS lookup duration (p50, p95, p99)

### Recommended Alerts

| Condition | Severity | Action |
|-----------|----------|--------|
| DNS timeout rate > 5% over 15 min | Warning | Check DNS resolver health |
| Rate limit hits > 10/hour globally | Warning | Check for automation abuse |
| Verification failure rate > 30% | Info | Review customer onboarding docs |
| DNS lookup p99 > 5 seconds | Warning | Check resolver latency |

## Quick Reference

| Parameter | Value |
|-----------|-------|
| Max retries | 2 |
| Base delay | 0.5s |
| Backoff | Exponential + 30% jitter |
| Cache TTL | 10 min (600s) |
| Rate limit | 10/hour/domain |
| Rate window | 1 hour (3600s) |
| Retriable errors | `Resolv::ResolvTimeout` only |

## Related Files

- `lib/onetime/domain_validation/sender_strategies/base_strategy.rb` - DNS lookup and caching
- `lib/onetime/security/dns_rate_limiter.rb` - Rate limiting
- `lib/onetime/operations/validate_sender_domain.rb` - Orchestration
- `lib/onetime/utils/retry_helper.rb` - Retry logic with backoff
