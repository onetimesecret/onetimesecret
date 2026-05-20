# docs/product/email-validation.md
---
title: Email Validation
type: reference
status: draft
updated: 2026-05-07
summary: How to use truemail-rb/truemail validation layers effectively in a SaaS context
---

For the **truemail-rb/truemail** Ruby gem (not the SaaS API service), validation layers work as follows:

## Validation Layers Available

| Layer                       | What It Checks                    | Speed   | Reliability                                            |
| --------------------------- | --------------------------------- | ------- | ------------------------------------------------------ |
| `:regex`                    | Syntax/format only                | Instant | Catches typos, not deliverability                      |
| `:mx`                       | DNS MX records exist              | Fast    | Verifies domain can receive mail                       |
| `:smtp`                     | Mailbox exists via SMTP handshake | Slow    | Most thorough; can be blocked by greylisting/firewalls |
| `:allow-list` / `:deny-list` | Domain/email overrides            | Instant | Bypass other checks                                    |

## Recommended Workflow for SaaS

**At account creation/update** (write path):

- Use `Truemail.validate(email, with: :mx)` or default (which includes regex → mx → smtp depending on config) [^1]
- This ensures the domain is valid and can receive email before you store it

**At transactional send time** (read path):

- A lightweight regex check is reasonable as a "gut check" — but **not strictly necessary if you validated at write time**
- The value depends on your data integrity model:

| Scenario                                        | Approach                                  |
| ----------------------------------------------- | ----------------------------------------- |
| Email never modified after validation           | No re-validation needed at send time      |
| Email pulled from DB after long delay           | Consider re-validation (domains go stale) |
| High-volume sender with strict reputation needs | Periodic re-validation or list hygiene    |

## Specific Answers to Your Questions

**Is `:mx` at send time necessary?**
No — if you validated at account creation and the record hasn't changed, re-running `:mx` is redundant. MX records rarely change, though they _can_.

**Regex-only at send time as a "gut check"?**
Acceptable and cheap. It catches data corruption or obvious garbage without network overhead. But it won't catch a domain that expired since signup.

**Better pattern for send-time:**

- If your mailing service (SendGrid, Mailgun, etc.) handles bounces gracefully, lean on their suppression lists
- If you need pre-send protection, consider a time-based re-validation strategy (e.g., re-check MX if `last_validated_at > 30.days.ago`)

## Configuration Best Practice

Set your default validation chain in `Truemail.configure` to match your strictest need (typically `:smtp` or `:mx` for signup), then use explicit `with:` only when you need to relax or tighten for specific calls [^1].

```ruby
# Typical SaaS config
Truemail.configure do |config|
  config.verifier_email = "verifier@yourdomain.com"
  config.default_validation_type = :mx # or :smtp
  config.validation_type_for = { "gmail.com" => :regex } # optional per-domain override
end
```

The gem's layered design lets you avoid redundant work: validate thoroughly once at entry, then trust your stored data unless you have specific reasons to suspect degradation.

[^1]: [truemail/README.md at master · truemail-rb/truemail · GitHub](https://github.com/truemail-rb/truemail/blob/master/README.md) (100%)
