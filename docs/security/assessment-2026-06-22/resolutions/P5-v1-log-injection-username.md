# P5 — Log injection via attacker-controlled Basic Auth username

- **Severity:** Low
- **Status:** Proposed fix
- **Affects default config?** Conditional — only in debug-enabled environments (`OT.ld`/`OT.debug?`)
- **Related:** P4 (same code path / Basic Auth branch). Findings 04 #5, §9.3.
- **Primary files:** `apps/api/v1/controllers/base.rb:67,73,80-81` (unsanitized `custid` in log lines),
  `lib/onetime/security/input_sanitizers.rb:40,104-106` (existing `NEWLINE_STRIP_PATTERN` / CR-LF stripping)

## Problem (recap)

V1's `authorized` interpolates the Basic Auth username (`custid`) into log lines without stripping
newlines:

```ruby
OT.ld "[authorized] Attempt for '#{custid}' via #{req.client_ipaddress} (basic auth)"        # :67
OT.ld "[authorized] '#{custid}' via #{req.client_ipaddress} (basic auth authenticated)"      # :73
```

`custid` is fully attacker-controlled — it is the username decoded from the `Authorization: Basic` header
(`base.rb:60`). With a plain-text logger, a `custid` containing CR/LF lets an attacker inject forged log
lines (log forging / log spoofing), e.g. fabricating a fake "authenticated" entry for another user or
breaking log-parsing tooling. It is `OT.ld` (debug level, gated by `OT.debug?` at `:79`), so exposure is
limited to debug-enabled environments, and a structured (JSON) logger that escapes field values would
neutralize it — but neither mitigation is guaranteed by default.

## Root cause

Untrusted, attacker-supplied identifiers are interpolated directly into a line-oriented log format. The
codebase already has the tools to prevent this (`InputSanitizers::NEWLINE_STRIP_PATTERN`, used for
email-header-injection defense at `input_sanitizers.rb:104-106`) but they are not applied to logged
identifiers. The sanitizers are opt-in per call site, so coverage depends on each caller remembering to
use them.

## Prescribed resolution

Sanitize/encode user-controlled fields before they reach a line-oriented log, and prefer structured logging
that escapes values. Apply consistently to all untrusted identifiers, not just this one site.

### Implementation steps

1. **Strip CR/LF (and other control characters) from `custid` before logging.** Reuse the existing
   pattern rather than inventing a new one. `InputSanitizers` is already mixed into the logic layer; expose
   a small helper (or call the existing constant) at the V1 controller log sites:

   ```ruby
   # apps/api/v1/controllers/base.rb
   # Strip CR/LF so an attacker-controlled username can't forge log lines.
   # NEWLINE_STRIP_PATTERN is the same constant used for email-header-injection
   # defense (input_sanitizers.rb:40,104-106).
   safe_custid = custid.to_s.gsub(Onetime::Security::InputSanitizers::NEWLINE_STRIP_PATTERN, '')

   OT.ld "[authorized] Attempt for '#{safe_custid}' via #{req.client_ipaddress} (basic auth)"
   # ... and likewise at :73 and the anonymous/:80-81 sites for any untrusted field ...
   ```

   Consider stripping all C0 controls (not only `\r\n`) for defense in depth — e.g. a
   `[\x00-\x1f\x7f]`-class strip — since some terminals/aggregators react to other control bytes. The
   minimum fix is CR/LF.

2. **Centralize so it can't be forgotten.** Add a single `sanitize_log_field`/`loggable(value)` helper
   (e.g. on `InputSanitizers` or a `LoggerMethods` mixin already used by the logic layer) that strips
   control characters, and route untrusted identifiers (`custid`, emails, domains, user agents) through it
   at every log site. This matches the codebase's existing approach of one shared sanitizer per concern and
   avoids repeating the inline `gsub`.

3. **Prefer structured logging that escapes values (strategic layer).** Where logs are emitted as JSON
   (the assessment notes a structured logger neutralizes this entirely, §9.3), pass `custid` as a discrete
   field rather than interpolating it into a message string, so the serializer escapes it:

   ```ruby
   OT.ld('[authorized] basic auth attempt', custid: safe_custid, ip: req.client_ipaddress)
   ```

   This is the durable fix — escaping at the logging boundary protects every field, not just the ones a
   developer remembered to pre-sanitize. The CR/LF strip in step 1 remains valuable as defense-in-depth for
   any plain-text logger path.

4. **Avoid logging the raw username at all where unnecessary.** These are `OT.ld` debug lines; for an
   *unauthenticated attempt* the username has little operational value and is attacker-controlled. Consider
   logging an obscured form (the limiters already obscure IPs, e.g. `feedback_rate_limiter.rb:146-153`) or
   only logging the username on the authenticated path. Combined with P4's constant-time fix, the
   "attempt" line can be reduced to a counter without the raw value.

### Alternatives considered

- **Rely on the logger being JSON in production:** correct that it neutralizes the issue, but it is a
  deployment assumption, not a guarantee, and plain-text/dev loggers remain vulnerable. Do the boundary
  escaping (step 3) *and* the cheap strip (step 1) so the fix holds regardless of logger config.
- **HTML/percent-encode the value:** wrong tool — these are log lines, not HTML; CR/LF (and control-char)
  stripping plus structured-field escaping is the appropriate encoding for the sink.
- **Drop the log lines entirely:** loses useful auth telemetry; sanitize/obscure instead of removing.

## Test / verification

- Send Basic Auth with a username containing `%0d%0a` / literal CR-LF (e.g.
  `Authorization: Basic base64("user\r\n[authorized] 'admin' ... (basic auth authenticated):token")`) with
  debug logging on → the emitted log contains a single line with the newline removed; no forged second line
  appears.
- Username with other control characters → control bytes stripped (if step 1 broadened to C0 controls).
- Structured-logger path: `custid` appears as an escaped JSON field value, not as injected message
  structure.
- Functional regression: normal usernames log unchanged (minus any trailing/embedded control chars);
  auth outcome is unaffected.

## Effort & risk

- **Effort:** Low — one helper + a few call-site changes; optionally extend to a `loggable` helper used
  across the logging layer.
- **Risk:** Low — purely log-formatting; no change to auth logic or stored data. Main care is applying the
  same helper at all untrusted-field log sites (`:67,:73,:80-81` here, and similar sites in
  `apps/api/v1/controllers/helpers.rb:86,113`) so the gap isn't reintroduced.
