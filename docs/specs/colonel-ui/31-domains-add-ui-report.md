Investigation: config wiring of /colonel/email-tools

How the page is structured

Three sections (AdminEmailTools.vue): Template Preview (read-only render), Test Send (dry-run + guarded real send), Deliverability (EmailDeliverabilitySection.vue — suppression tiles, suppression list, event feed). All hit /api/colonel/email/* logic classes backed by the EmailSuppression Redis model and the shared Onetime::Operations::Email::* ops.

EMAILER_MODE — connected, but only transiently and partially

EMAILER_MODE → emailer.mode → Mailer.determine_provider (mailer.rb:195) → the sending transport (ses|sendgrid|lettermint|smtp|logger).

On the page it surfaces in exactly one place: the Test Send dry-run diagnostic provider field (send_test_email.rb success_data → details.provider). There is no standing indicator of the active mailer mode/provider anywhere on the page — an operator only learns the provider by typing an address and running a dry-run.

Two correctness/clarity notes on that diagnostic:
- host = Socket.gethostname (the app server's own hostname, send_test.rb build), not the SMTP/ESP host. An operator will read "Host" as the mail host. Misleading label.
- from correctly reflects Mailer.from_address (config from → FROM_EMAIL).

CUSTOM_MAIL_PROVIDER — not connected at all

CUSTOM_MAIL_PROVIDER → emailer.sender_provider → Mailer.determine_sender_provider (mailer.rb:180). Per docs/architecture/custom-mail-sender-ses.md this is deliberately decoupled: it selects the custom-domain sender-domain provisioning provider (white-label SES provisioning), not the transactional transport.

It appears nowhere on the email-tools page, and — more importantly — the suppression sync ignores it. SyncProviderFeedback defaults provider to determine_provider (the transport), so bounce/complaint feedback for a custom mail sender domain provisioned via a different SES account/region is not pulled by the default sync path. That's a real blind spot if custom sender domains are live.

Suppressions / stats — connected only through an operator-driven sync

The four tiles (get_email_deliverability.rb) read the EmailSuppression Redis model, not the ESP live. Data reaches that model three ways (documented in the model header):
1. Active pull — SyncProviderFeedback (SES ListSuppressedDestinations / Lettermint), run by bin/ots email sync-feedback. No cron is wired in the repo — it's purely operator-invoked. If nobody runs it, the tiles read zero/stale.
2. Passive ingest — operator relay POSTs to /email/deliverability/events (IngestFeedback).
3. Synchronous SMTP 5xx at send time.

The page shows no "last synced" timestamp, no source provider, and no signal that sync is even configured — so an empty suppression list is indistinguishable from "sync never ran."

The concrete gap

bin/ots email config (config_command.rb) already computes exactly the standing diagnostic an operator wants: provider, auto_detected, from_address, from_name, and a masked provider_config (host/port/region/has_credentials). It has no colonel HTTP endpoint and no UI surface. The one endpoint that does expose emailer config, GetSystemSettings (/config, the separate System Settings page), dumps the raw emailer hash unmasked (get_system_settings.rb:40) — including user/pass — unlike its billing/redis sections which are masked. That's an adjacent credential-exposure concern worth flagging.

Verdict: Test Send is correctly wired to EMAILER_MODE (via determine_provider) but exposes it only transiently and with a misleading host. CUSTOM_MAIL_PROVIDER is entirely absent and the suppression sync structurally ignores it. Stats are real but depend on an unscheduled, invisible sync. The page is missing the standing "what is my mail config and is it healthy" panel that the CLI already computes.

---
Suggested functions for a SaaS admin email-tools & safety page

Close the config gap first (highest value, lowest cost):
1. Mailer Configuration panel — surface email config via a new read-only colonel endpoint: active provider, auto_detected flag, from address/name, masked provider config, and whether sender_provider/CUSTOM_MAIL_PROVIDER differs from the transport. This is the direct answer to "is it connected."
2. Sync status on the deliverability tiles — last-sync timestamp, source provider(s), and a "sync not configured/never run" warning. Optionally a "Sync now" button (audited) wrapping SyncProviderFeedback for all configured providers (transport and sender_provider).
3. Fix the host label — show the real transport endpoint (SMTP host / SES region), or rename to "Origin host" so it isn't mistaken for the mail host.

Standard SaaS email-safety features not yet present:
4. Send-mode / safety banner — prominent indicator when provider is logger/disabled (mail is being dropped) or when a test-mail redirect/allowlist is active. Prevents "why aren't emails arriving" confusion.
5. Outbound rate / volume stats — emails_sent, sends/hour, and bounce-rate & complaint-rate percentages (not just raw counts) with reputation thresholds (SES complaint >0.1%, bounce >5% highlighted). Counts alone don't tell an operator if reputation is at risk.
6. Add-to-suppression (manual) — the UI only removes suppressions; operators routinely need to manually suppress an address (the reason: 'manual' ingest path exists in the model but isn't exposed).
7. Bulk/export suppression list — CSV export for portability between ESPs and audits.
8. DNS / auth health check — SPF, DKIM, DMARC, and MX lookup for the sending domain(s), including custom sender domains. This is the single most-common "email admin" panel in SaaS and pairs naturally with the existing custom-domain provisioning.
9. Recent send log / failure feed — beyond bounces: last N send attempts with status, so a failed transactional send is diagnosable without SSH.
10. Per-recipient deliverability lookup — given an address: is it suppressed, why, when, and its recent bounce/complaint events (the data exists; it's just not queryable per-address beyond the exact-match suppression search).

Safety hardening (adjacent findings):
11. Mask emailer credentials in GetSystemSettings (get_system_settings.rb:40) the way billing/redis already are.

If you want, I can turn items 1–3 (the actual config-wiring fixes) into a scoped implementation plan or file an issue.
