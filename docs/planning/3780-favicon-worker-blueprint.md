I have everything I need. Gems confirmed present: `nokogiri 1.19.4`, `fastimage 2.4.1`, `chunky_png 1.4.0`, `httparty`, `public_suffix`. Absent: `mini_magick`, `ruby-vips` — settles ICO handling (passthrough, no native dep) and discovery (in-house Nokogiri, no `favicon_get`). Trigger insertion point and icon-write shape confirmed. Here is the blueprint.

---

# Implementation Blueprint — #3780 Background worker: auto-fetch custom-domain favicon

## Design decisions locked by the acceptance criteria (not open)

- **Archetype = Sneakers queue worker**, not scheduled. AC "consumes `domain.favicon.fetch`, auto-discovered, passes `ots worker --check`" is decisive; Map 6's scheduled-vs-queue ambiguity is resolved.
- **Storage = `custom_domain.icon` hashkey**, in the exact shape `UpdateDomainImage` writes. AC "populates `custom_domain.icon` and GetFavicon serves it" settles Map 3/Map 4's "URL string vs image record" question. `favicon_url` in BrandSettings is **not** touched.
- **New DLX/DLQ `dlx.domain.favicon`/`dlq.domain.favicon`**, not a reuse of `dlx.domain.validation`. Favicon is a distinct failure family with independent replay/triage (Map 2 gotcha #1). The `^dlq\.` TTL policy auto-covers it.
- **`favicon_get` is rejected for the network path.** Its discovery HTTP hop happens inside the gem where an IP pin cannot reach and it follows redirects to un-validated hosts (Map 5 gotcha #3). Nokogiri is already a dep, so discovery is done in-house under the SSRF guard. This is required to satisfy "SSRF guard rejects … incl. via redirect."
- **ICO = passthrough, no `mini_magick`/`ruby-vips`.** Store fetched `.ico` bytes with `content_type: image/x-icon`; fix GetFavicon to serve the stored content-type instead of hardcoding `image/png`. Browsers render `.ico` natively. High-quality ICO→32×32 PNG normalization is deferred (open question 3).
- **Trigger = `Onetime::Operations::VerifyDomain#verify_single`** on the reachable transition, gated by the feature flag. Manual-refresh UI (Map 4 Trigger B, the full Vue chain) is **out of scope** — no AC references it. Deferred to open question 5.

---

## 1. Files to create and modify

### Create

| Path | Purpose |
|---|---|
| `lib/onetime/http/safe_fetch.rb` | `Onetime::Http::SafeFetch` — the SSRF-guarded HTTP fetcher (pre-resolve + validate, IP-pinned connect, per-hop re-validation, redirect cap, timeouts, streamed size cap, content-type + magic-byte checks, SVG rejection). Section 3. |
| `lib/onetime/operations/fetch_domain_favicon.rb` | `Onetime::Operations::FetchDomainFavicon` — the unit of work shared by the worker AND the jobs-disabled inline fallback. Discovers (`/favicon.ico`, then Nokogiri `<link rel=icon>`), fetches via SafeFetch, normalizes, applies the overwrite guard, writes the `icon` hash + lifecycle/outcome fields. Mirrors `ValidateSenderDomain`'s role (Map 2 `enqueue_domain_validation` inline call). |
| `lib/onetime/jobs/workers/favicon_fetch_worker.rb` | `Onetime::Jobs::Workers::FaviconFetchWorker` — thin Sneakers wrapper. Copy the **single-status** shape of `dns_record_check_worker.rb:73-121` (Map 1), not the dual-worker `DomainValidationWorker`. Delegates to the operation. |
| `try/unit/http/safe_fetch_try.rb` | SSRF unit tryout (blocks 169.254.169.254 / 127.0.0.1 incl. via redirect; redirect cap; timeout; max-size; SVG reject; ICO accept). |
| `try/unit/operations/fetch_domain_favicon_try.rb` | Operation tryout: populates `icon`, overwrite guard, no-favicon = COMPLETED-false, error = FAILED. |
| `spec/lib/onetime/jobs/workers/favicon_fetch_worker_spec.rb` | Worker RSpec: idempotency dup no-op, transient retry, hard-failure DLQ, ping.test, `--check` drift via `QueueDeclarator.validate_worker!`. |

### Modify

| Path | Change | Anchor |
|---|---|---|
| `lib/onetime/jobs/queues/config.rb` | Add `'domain.favicon.fetch'` to `QUEUES` (`durable:true, auto_delete:false, arguments:{'x-dead-letter-exchange'=>'dlx.domain.favicon'}`); add `'dlx.domain.favicon'=>{queue:'dlq.domain.favicon',arguments:{}}` to `DEAD_LETTER_CONFIG`. No `DLQ_POLICIES` edit (`^dlq\.` covers it). | after `'domain.dns.check'` entry (~L70) and after `'dlx.domain.validation'` (~L111-112) |
| `lib/onetime/jobs/publisher.rb` | Add class delegator `enqueue_favicon_fetch(domain_id)` (mirror L110-112) + instance method with `jobs_enabled?` inline fallback that `require`s + calls `Onetime::Operations::FetchDomainFavicon`, else `publish('domain.favicon.fetch', {domain_id:, requested_at: Time.now.utc.iso8601})`. Domain-family shape (no `FALLBACK_STRATEGIES`). | class L110-124; instance after `enqueue_dns_record_check` L300-338 |
| `lib/onetime/models/custom_domain.rb` | Add object-hash fields: `field :favicon_fetch_status` (JobLifecycle), `field :favicon_fetched` (outcome bool), `field :favicon_fetch_error`, `field :favicon_fetch_completed_at`. Icon hashkey already exists (L101). | fields block near L90-94 |
| `lib/onetime/operations/verify_domain.rb` | Insert guarded `Onetime::Jobs::Publisher.enqueue_favicon_fetch(domain.identifier)` on the reachable transition, wrapped in `rescue` so it never breaks verification. Covers both the API verify and the scheduled `domain_refresh_job` (Map 4 gotcha #2). | immediately after `current_state = domain.verification_state` (**verified L154**) |
| `apps/api/domains/logic/domains/update_domain_image.rb` | In `UpdateDomainImage#process`, stamp `_image_field['favicon_source'] = 'user_upload'` and `_image_field.delete('encoded_favicon')` (clear stale cache on re-upload). | after L123 (the 7-key write) |
| `apps/web/core/logic/page/get_favicon.rb` | In `serve_custom_favicon`: branch on stored `content_type`. For ICO types (`image/x-icon`, `image/vnd.microsoft.icon`) decode `encoded` and serve as `image/x-icon` with **no** ChunkyPNG resize; else keep the PNG resize/cache path. Fixes the hardcoded `image/png` at **L108**. | `serve_custom_favicon` L86-110 |
| `etc/defaults/config.defaults.yaml` | Add `jobs.favicon_fetch` block (Section 5). Inline literals, no `JOBS_*` env (post-#3775 rule). | after `expiration_warnings` (~L938) |
| `src/schemas/contracts/config/section/jobs.ts` | Add `jobsFaviconFetchSchema` (field names + types, all `.optional()`), register `favicon_fetch: jobsFaviconFetchSchema.optional()` in `jobsSchema`. | mirror `jobsDomainRefreshSchema` L31-36; register L93-106 |
| `try/unit/config/jobs_config_defaults_try.rb` | Add a `favicon_fetch` pure-defaults assertion alongside `domain_refresh`/`expiration_warnings`. | L55-61 |

No change needed to: `worker_command.rb` (auto-discovery via glob L361 + `ObjectSpace` scan), `queue/status_command.rb` (enumerates `QUEUES.each_key` L122 + `DEAD_LETTER_CONFIG.each_key` L150 — the queue + DLX appear automatically, satisfying "documented in queue status tooling"), `remove_domain_image.rb` (`favicon_source` is a subkey wiped by `delete!`).

---

## 2. Build sequence

**Wave 1 — four independent tracks (parallelize):**

- **A. SSRF module** — `lib/onetime/http/safe_fetch.rb` + `try/unit/http/safe_fetch_try.rb`. Security-critical, pure Ruby, no other deps. **Agent: ruby-dev.** (Start first; longest pole.)
- **B. Queue topology + Publisher** — `queues/config.rb` (QUEUES + DEAD_LETTER_CONFIG) then `publisher.rb` enqueue methods. `sneakers_options_for` must resolve before the worker file loads (Map 1 gotcha #3), so config lands before Wave 2. **Agent: backend-dev.**
- **C. Storage + serving** — `custom_domain.rb` fields; `update_domain_image.rb` `favicon_source` stamp + cache clear; `get_favicon.rb` ICO serve fix. **Agent: backend-dev.**
- **D. Config surface** — `config.defaults.yaml` block + `jobs.ts` Zod + `jobs_config_defaults_try.rb`. The 4-place checklist (`config.rb:13-26`). **Agent: backend-dev.**

**Wave 2 — depends on A + C:**

- **E. Operation** — `lib/onetime/operations/fetch_domain_favicon.rb`. Consumes `SafeFetch` (A), writes the `icon` hash + status fields (C), reads the `favicon_source` guard (C), reads the config knobs (D). **Agent: backend-dev.** Depends on A, C, D.

**Wave 3 — depends on B + E:**

- **F. Worker** — `favicon_fetch_worker.rb`. `from_queue **QueueDeclarator.sneakers_options_for('domain.favicon.fetch')` (needs B) delegating to the operation (E). Verify `ots worker --check` prints the new worker. **Agent: backend-dev.** Depends on B, E.
- **G. Trigger + inline fallback** — `verify_domain.rb` enqueue insertion; the Publisher inline branch (B) requires the operation (E). **Agent: backend-dev.** Depends on B, E.

**Wave 4 — depends on all impl:**

- **H. Tests** — worker RSpec + operation/SSRF tryouts filled in against real behavior; run `try --agent` and the worker spec. **Agent: qa-automation-engineer.** Depends on E, F, G.

Critical path: **A → E → F/G → H.** B, C, D run fully in parallel with A.

---

## 3. SSRF module design — `Onetime::Http::SafeFetch`

Building blocks: **`Resolv::DNS`** for A/AAAA resolution (Map 5 `base_strategy.rb:152-172` retry/cache pattern), **`IPAddr`** for CIDR membership (Map 5 `detect_host.rb:240-263` shape — but the range list is **replaced**, not reused), **`Net::HTTP`** with `#ipaddr=` for the IP-pinned connect (Map 5 `probe.rb:103-116` timeout/TLS skeleton), **`FastImage`** for magic-byte type sniffing (already a dep).

```ruby
module Onetime
  module Net
    class SafeFetch
      Result = Struct.new(:body, :content_type, :final_url, keyword_init: true)

      class Error               < Onetime::Problem; end
      class BlockedTarget       < Error; end   # resolved to private/link-local/metadata
      class TooManyRedirects    < Error; end
      class ResponseTooLarge    < Error; end
      class DisallowedContentType < Error; end
      class FetchTimeout        < Error; end   # transient → retriable

      ALLOWED_SCHEMES = %w[https].freeze          # https-only for MVP (open Q6)
      ALLOWED_PORTS   = [443].freeze

      # Deny-by-default: reject unless the resolved IP is in NONE of these.
      BLOCKED_V4 = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
                      169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
                      198.18.0.0/15 224.0.0.0/4 240.0.0.0/4].map { |c| IPAddr.new(c) }
      BLOCKED_V6 = %w[::1/128 ::/128 fc00::/7 fe80::/10 ff00::/8
                      ::ffff:0:0/96 64:ff9b::/96 2001:db8::/32].map { |c| IPAddr.new(c) }

      def initialize(timeout:, max_bytes:, max_redirects:, allowed_content_types:)

      # Fetch an image. Follows ≤max_redirects redirects, re-resolving+re-validating
      # the host at EVERY hop. Returns Result or raises one of the errors above.
      def get_image(url)

      # Fetch text/html for favicon discovery (same guard, no image validation,
      # size-capped). Returns the body string.
      def get_html(url)

      private

      # Core: scheme/port check → resolve_and_validate! → fetch_pinned → redirect loop.
      def fetch(url, redirects_left:, allow_html:)

      # Resolve host A + AAAA via Resolv::DNS; validate EVERY address; fail-closed:
      # raise BlockedTarget if ANY resolved IP is blocked. As built, returns ALL
      # validated addresses IPv4-first; #fetch dials them in order, falling through
      # on connect-level route errors (broken dual-stack resolves AAAA it can't route).
      def resolve_and_validate!(host)
        addrs = Resolv::DNS.open { |dns| dns.getaddresses(host) }   # [Resolv::IPv4|IPv6]
        raise BlockedTarget, "no A/AAAA for #{host}" if addrs.empty?
        addrs.each { |a| raise BlockedTarget, "blocked #{a}" if blocked_ip?(IPAddr.new(a.to_s)) }
        addrs.map(&:to_s)  # v4 sorted ahead of v6
      end

      def blocked_ip?(ip)
        ip = ip.native if ip.ipv6? && ip.ipv4_mapped?     # unwrap ::ffff:a.b.c.d → v4
        return true if ip.link_local?                      # Ruby 3.4.9 (Map 5): catches 169.254.169.254
        (ip.ipv4? ? BLOCKED_V4 : BLOCKED_V6).any? { |net| net.include?(ip) }
      rescue IPAddr::InvalidAddressError
        true                                               # fail closed
      end

      # Pin the connect to the validated IP; keep Host header + TLS SNI = hostname.
      def fetch_pinned(uri, validated_ip)
        http = ::Net::HTTP.new(uri.host, uri.port)
        http.ipaddr      = validated_ip                    # ← TOCTOU mitigation: no re-resolve at connect
        http.use_ssl     = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = http.read_timeout = @timeout
        # single GET, NO Net::HTTP redirect follow; stream body with a byte cap:
        http.request_get(uri) do |resp|
          # early reject on declared Content-Length
          raise ResponseTooLarge if resp.content_length.to_i > @max_bytes
          buf = +''
          resp.read_body { |chunk| buf << chunk; raise ResponseTooLarge if buf.bytesize > @max_bytes }
          return [resp, buf]
        end
      rescue ::Net::OpenTimeout, ::Net::ReadTimeout => ex
        raise FetchTimeout, ex.message
      end

      # Magic-byte validation. Accept :png and :ico; reject :svg and everything else.
      def validate_image_bytes!(bytes, declared_type)
        raise DisallowedContentType, 'svg' if bytes.lstrip.start_with?('<?xml', '<svg')
        type = FastImage.type(StringIO.new(bytes))         # magic-byte, not the HTTP header
        raise DisallowedContentType, type.inspect unless %i[png ico].include?(type)
      end
    end
  end
end
```

**Redirect handling:** the `fetch` loop reads `resp['location']` on 3xx, resolves it (absolute or relative-to-current), enforces scheme+port again, calls `resolve_and_validate!` on the **new** host, decrements `redirects_left`, and raises `TooManyRedirects` at zero. Every hop is independently IP-pinned — a `Location: http://169.254.169.254/` is rejected at the re-validation, satisfying "SSRF … incl. via redirect."

**DNS-rebinding / TOCTOU residual (flagged):** `http.ipaddr = validated_ip` pins the TCP connect to the exact address we validated, so **no second DNS resolution happens at connect** — the classic validate-then-reresolve rebind window is closed for the connect itself (Map 5 gotcha #5). Residual: (a) TLS SNI/`Host` still carry the hostname (required for cert verification — correct, not a leak); (b) a poisoned/rotating DNS answer at *resolution time* is out of scope for a favicon fetch. Fail-closed on *any* blocked address in the RRset prevents an attacker from mixing one public + one private A-record. This is exactly why `favicon_get` is not used: its internal discovery socket cannot be pinned.

---

## 4. Overwrite-policy design — uploads win over fetches

**One tag, on the `icon` hashkey (per-image subkey, auto-wiped by `delete!`):** `icon['favicon_source']`.

- **User upload** → `update_domain_image.rb#process` stamps `'user_upload'` after the 7-key write (verified L117-123) and `delete('encoded_favicon')` to drop the stale cache.
- **Fetch worker** → the operation stamps `'auto_fetch'`.

**Worker guard (the load-bearing rule).** Before writing, the operation refreshes and checks:

```ruby
existing_filename = custom_domain.icon['filename'].to_s
existing_source   = custom_domain.icon['favicon_source'].to_s
if !existing_filename.empty? && existing_source != 'auto_fetch'
  # user_upload OR legacy pre-tag upload → never clobber
  record COMPLETED, favicon_fetched: (outcome unchanged); ack
  return
end
```

Testing `filename present && source != 'auto_fetch'` protects **both** tagged `user_upload` icons **and legacy icons uploaded before the tag existed** (they have `filename` but no `favicon_source`). This satisfies "user-uploaded icon NEVER overwritten by a fetch" without a data migration.

**On a permitted write**, the operation writes the full `UpdateDomainImage` shape into `icon` — `encoded`, `filename`, `content_type`, `height`, `width`, `ratio`, `bytes` — plus `favicon_source='auto_fetch'`, and `delete('encoded_favicon')` so GetFavicon regenerates on next request.

**GetFavicon precedence is NOT changed** for the strict AC. The only writer that could clobber user content is the worker (guarded above); `GetFavicon#generate_and_cache_favicon` only writes the derived `encoded_favicon` cache, never `encoded`/`filename`, so it cannot clobber a user icon. Whether a *fetched icon* should outrank a *user-uploaded logo* in `raise_concerns` (icon>logo, L54-67) is a product call — open question 4.

---

## 5. Config block

Add to `etc/defaults/config.defaults.yaml` after `expiration_warnings` (~L938), mirroring the `domain_refresh` idiom (L915-922). Inline literals only — no `JOBS_*` ERB (post-#3775 rule; nothing outside YAML reads these):

```yaml
  # Auto-fetch custom-domain favicon from the live domain (#3780)
  favicon_fetch:
    enabled: false          # feature flag — default OFF
    timeout: 5              # seconds per HTTP fetch (connect + read)
    max_response_bytes: 102400   # 100 KB ceiling, streamed-enforced
    max_redirects: 3
    # Array REPLACES on override (deep_merge, config.rb:1125-1133) — restate in full to change.
    # SVG intentionally excluded (script/XXE risk) — reject at fetch time.
    allowed_content_types:
      - image/x-icon
      - image/vnd.microsoft.icon
      - image/png
```

**Runtime reads (mandatory `.dig` + fallback — the `jobs` tree is absent from the in-code `DEFAULTS` hash, Map 6 gotcha):**

```ruby
OT.conf.dig('jobs','favicon_fetch','enabled') == true
OT.conf.dig('jobs','favicon_fetch','timeout')            || 5
OT.conf.dig('jobs','favicon_fetch','max_response_bytes') || 102_400
OT.conf.dig('jobs','favicon_fetch','max_redirects')      || 3
OT.conf.dig('jobs','favicon_fetch','allowed_content_types') || %w[image/x-icon image/vnd.microsoft.icon image/png]
```

**`spec/config.test.yaml` consideration:** the test-mode `jobs:` block (L124-133) does **not** mention `favicon_fetch`, so the defaults survive the deep-merge and `enabled` is `false` in test — fine for runtime. But the pure-defaults **tryout** (`jobs_config_defaults_try.rb`) must NOT assert against `OT.conf['jobs']` (that's defaults ⋈ `config.test.yaml`); it must `Onetime::Config.load(@defaults_path)['jobs']` with `JOBS_*` env scrubbed (the named memory trap; pattern at L31-40).

**Zod** (`jobs.ts`, mirror `jobsDomainRefreshSchema` L31-36):

```ts
const jobsFaviconFetchSchema = z.object({
  enabled: z.boolean().optional(),
  timeout: z.number().optional(),
  max_response_bytes: z.number().optional(),
  max_redirects: z.number().optional(),
  allowed_content_types: z.array(z.string()).optional(),
});
// register in jobsSchema (L93-106):
favicon_fetch: jobsFaviconFetchSchema.optional(),
```

---

## 6. Test plan (1:1 to acceptance criteria)

Trap awareness: single-file tryouts run `boot(:test, false)` which **skips encryption** ("Key version cannot be nil") — export CI secrets or `boot true` locally (memory: `tryouts_boot_false_skips_encryption`). Config-resolution assertions must use the explicit-path load, never `OT.conf` (test-merge trap, Map 6).

| AC | Test | File |
|---|---|---|
| Worker consumes `domain.favicon.fetch`, auto-discovered, passes `--check` | `QueueDeclarator.validate_worker!(FaviconFetchWorker)` drift check; assert `sneakers_options_for('domain.favicon.fetch')` resolves; shell-assert `ots worker --check` exits 0 and lists the class | `favicon_fetch_worker_spec.rb` |
| Fetch populates `icon` + GetFavicon serves end-to-end | Operation writes `icon['encoded'/'filename'/'content_type']`; then drive `GetFavicon` and assert non-default bytes served | `fetch_domain_favicon_try.rb` + a `get_favicon` case |
| SSRF blocks 169.254.169.254 **and** 127.0.0.1 incl. via redirect | `get_image` raises `BlockedTarget` for hosts resolving to each; a stub redirect `→ http://169.254.169.254/` also raises | `safe_fetch_try.rb` |
| Redirect cap / timeout / max-size enforced | `TooManyRedirects` at cap+1; `FetchTimeout` on a slow stub; `ResponseTooLarge` on an oversized stub (both Content-Length and streamed-chunk paths) | `safe_fetch_try.rb` |
| User-uploaded icon NEVER overwritten | Seed `icon` with `favicon_source='user_upload'` (and a legacy `filename`-only case) → operation returns without writing `encoded` | `fetch_domain_favicon_try.rb` |
| Idempotency dup no-op / transient retry / hard-failure DLQ | Second `claim_for_processing(msg_id)` → `ack!` no write; retriable `FetchTimeout` retries then succeeds; unexpected `StandardError` → `reject!` (DLQ) | `favicon_fetch_worker_spec.rb` |
| `jobs_enabled? == false` → sync fallback | With `$rmq_channel_pool = nil`, `Publisher.enqueue_favicon_fetch` runs the operation inline and returns true | `favicon_fetch_worker_spec.rb` or a publisher tryout |
| Flag defaults OFF; knobs configurable | Pure-defaults tryout asserts `{'enabled'=>false,'timeout'=>5,'max_response_bytes'=>102400,'max_redirects'=>3,'allowed_content_types'=>[...]}` via explicit-path load | `jobs_config_defaults_try.rb` |
| `.ico` normalized/served correctly | Store an `.ico` in `icon`; assert GetFavicon serves `image/x-icon` bytes unmodified (no ChunkyPNG); assert SVG bytes rejected upstream by SafeFetch | `safe_fetch_try.rb` + `get_favicon` case |
| Queue + DLQ in status tooling | Assert `QueueConfig::QUEUES` and `DEAD_LETTER_CONFIG` contain the new keys (status enumerates them automatically) | queue-config tryout |

---

## 7. Open questions / decisions for the human

1. **Trigger reachability gate — `:resolving` vs `:verified`?** Favicon fetch only needs `resolving==true`, which `:resolving` already satisfies, but branding may want to wait for full `:verified`. I've written the guard as `%i[resolving verified].include?(current_state)` on the transition; confirm the intended threshold (Map 4 open Q2).
2. **Re-fetch policy on periodic re-verification.** Fire only on the first transition into reachable (my default via `current_state != previous_state`), or re-fetch every cycle, or only when no favicon is set? Affects whether the worker skips when `icon` already has an `auto_fetch` favicon (Map 4 open Q3).
3. **ICO→PNG normalization depth.** MVP is ICO passthrough (`image/x-icon`, no resize) — zero new deps. True 32×32 downscaling of `.ico`/JPEG/WebP needs `mini_magick` (ImageMagick) or `ruby-vips` (libvips) — a native runtime dependency and a supply-chain call. Ship passthrough now, add a converter later? (Map 3 open Q4.)
4. **Fetched-icon vs user-uploaded-logo precedence.** GetFavicon serves `icon` over `logo` (L54-67). After this feature, a *fetched* icon will outrank a user's *uploaded logo*. AC only protects the uploaded *icon*; is overriding the logo acceptable, or should `raise_concerns` prefer a `user_upload` logo over an `auto_fetch` icon? (Map 3 open Q1.)
5. **Manual "refresh favicon" UI (Trigger B) — in scope?** No AC references it; it's the full `domainsStore → brandStore → useBranding → BrandEditor → SimpleBrandPanel → BrandLogoField` chain plus a `RefreshDomainFavicon` logic class (Map 4). Recommend deferring to a follow-up PR.
6. **HTTP vs HTTPS-only for the fetch.** I locked `ALLOWED_SCHEMES=['https']` (verified custom domains have SSL; avoids downgrade surface). Some legitimate favicons are HTTP-only — allow `http` behind a config flag, or stay https-only?
7. **DLX naming confirmation.** Locked `dlx.domain.favicon`/`dlq.domain.favicon` (independent replay/triage). Confirm the maintainer prefers this over reusing `dlx.domain.validation` (Map 2 recommends new; both precedents exist).
8. **`CustomDomain` persistence primitive.** The worker writes status via `save_fields(:favicon_fetch_status, …)` to avoid racing `verify_domain`'s `domain.save`. Confirm `CustomDomain` (Familia::Horreum) exposes `save_fields` like `MailerConfig` does, and confirm the loader is `Onetime::CustomDomain.load(domain_id)` where `domain_id == identifier == objid` (Map 4).
