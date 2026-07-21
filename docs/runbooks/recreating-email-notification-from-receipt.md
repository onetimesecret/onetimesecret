# Recreating an email notification from a receipt

_Created: 2026-07-20_

## Follow-up improvements

Items 1 & 2 concerned the dead-letter queue and have been dropped from this
list — the DLQ recovery path is documented below under "First check the dead
letter queue." (The DLQ is still in use; the stack runs RabbitMQ 4.2.)

3. Fail fast and loud at boot, not at first send

The port block was invisible until an email actually tried to go out — potentially hours after deploy. You already have bin/ots email test and the delivery machinery; status_command does not probe SMTP.

Implement: a startup/readiness SMTP connectivity probe — a TCP connect (or full openssl s_client STARTTLS+AUTH) to SMTP_HOST:SMTP_PORT at boot or in a healthcheck. If it can't reach the mail server, log it at ERROR and fail the readiness check. This matches your own "fail fast and loud" rule: a blocked port should break the deploy's health signal, not the first user's secret. Wire the existing Operations::Email::SendTest probe (dry-run mode) into status/healthcheck.

4. Deployment docs: the DO port trap

DigitalOcean blocks 25/587/465 by default; 2587/2465 are SES's escape hatches. This will bite the next person who spins up a droplet. The config generator (config_generator.rb:249) emits SMTP_HOST/USERNAME/PASSWORD — add a comment there and a docs note: "On DigitalOcean and similar hosts, 587 is often blocked — use 2587 (STARTTLS) or 2465 (implicit TLS)." Cheap, high-recall.

5. SMTP_AUTH is a lie — honor it or delete it

smtp.rb:144 hardcodes authentication: :plain and ignores the SMTP_AUTH=login env var entirely. It happens to work because SES accepts both, but a config var that silently does nothing is false confidence during exactly the kind of debugging you just did. Either read ENV['SMTP_AUTH'] or remove the var from docs/config generation.

Lower priority

- Incident log clarity: the async SemanticLogger lag made "18:36" look stuck when it was fine. On the success path the worker doesn't flush_logs (only on failure). A per-delivery flush, or a synchronous appender for delivery events, removes that red herring during the next incident.
- Promote the receipt-resend to a real command: you needed an ad-hoc console script. bin/ots email resend-incoming --since --until (with the live-secret guard the script already had) would make that a supported, tested recovery tool instead of paste-in Ruby. Only worth it if DLQ replay isn't always sufficient — but the auto-consumer's discard behavior (#2) means it sometimes won't be.

---

## First check the dead letter queue.

```bash
bin/ots queue dlq list

 ══════════════════════════════════════════════════════════════════════
 Dead Letter Queue Summary
 ══════════════════════════════════════════════════════════════════════

 Queue                            Messages  Consumers
 ----------------------------------------------------------------------
 dlq.email.message                       9          0
 dlq.notifications.alert                 0          0
 dlq.webhooks.payload                    0          0
 dlq.billing.event                       0          0
 dlq.domain.validation                   0          0
 dlq.migration.customer                  0          0
 ----------------------------------------------------------------------
 Total
```

bin/ots queue dlq list email.message

This is the precise recovery path — use it instead of receipt reconstruction. Note the real short name is email.message (not email.message.send — I had the queue name wrong earlier).

Act now, before any dlq_consumer tick can discard the non-auth (incoming) ones.

Inspect, then replay

# 1. Confirm these 9 are the incoming-secret notifications

podman exec -it <container> bin/ots queue dlq list email.message

# 2. (optional) Look at one in detail — check the template field

podman exec -it <container> bin/ots queue dlq show email.message --id <ID>

You're looking for template: incoming_secret (or raw Rodauth auth mails). If all 9 are the incoming notifications, replay them:

# 3. Replay all back to the live queue — workers deliver via 2587 now

podman exec -it <container> bin/ots queue dlq replay email.message

# 4. Watch them drain

podman exec <container> bin/ots queue status

Why replay beats reconstruction here

The DLQ messages are the original enqueued payloads — exact recipient, locale, memo, domain_id, everything as originally sent. Replay is a faithful re-delivery. Reconstruction from receipts was the fallback for a drained DLQ; you don't need it — keep it in your back pocket only if some messages fail again.

Two things to watch

1. Idempotency: replay re-delivers all 9. If any of those secrets were already viewed/burned since the outage, the email still goes out but the link is dead — low harm, but worth knowing. (Unlike the reconstruction script, replay does not skip consumed secrets, because it doesn't reload them — it just re-sends the stored payload.)
2. If a replayed message fails again it lands back in the DLQ. After replay, re-run dlq list email.message — a count of 0 means all delivered; any remainder is a genuine per-message problem (bad recipient, etc.) worth a dlq show.

Run step 1 and paste the output — confirm the 9 are incoming_secret before replaying.

---

## Recreate email jobs from receipts

Confirmed everything. Publisher.enqueue_email(template, data, domain_id:) is the exact call, and Receipt.instances is a sorted set scored by created, so you can range it by your outage window.

First, the config check you couldn't do (config get doesn't exist — only validate):

# inside the container, in the console:

podman exec -it <container> bin/ots console
OT.conf.dig('jobs', 'dlq_consumer', 'enabled') # true = the auto-purger is running

Reconstruction — run inside bin/ots console

Why this is safe (and its one limitation)

- Natural guard: receipt.load_secret returns nil if the secret was already viewed/burned or expired. So already-delivered-and-opened secrets are automatically skipped — you only re-notify secrets that are still live and unviewed.
- Limitation: receipts have no "notified_at" field, so this cannot tell sent from failed. It re-notifies every live, unviewed incoming receipt in the window — including any whose original email actually got through but hasn't been opened yet. The duplicate is the identical one-time link, so harm is low, but know that it's a superset, not a precise replay. (DLQ replay is precise; this is the fallback for when the DLQ is already drained.)

Step 1 — Dry run (lists, sends nothing)

Edit the two timestamps to bracket your outage, then paste:

# --- outage window (local paste: set these) ---

outage_start = Time.parse('2026-07-20 14:00 UTC').to_i # when the port block began
restart_at = Time.parse('2026-07-20 18:30 UTC').to_i # when you switched to 2587
DRY_RUN = true

# ----------------------------------------------

ids = Onetime::Receipt.instances.rangebyscoreraw(outage_start, restart_at)
puts "Receipts created in window: #{ids.size}"

candidates = ids.filter_map do |id|
r = Onetime::Receipt.load(id) rescue nil
next unless r
next unless r.source.to_s == 'incoming' # incoming feature only
next if r.recipients.to_s.empty? # must have a recipient
s = r.load_secret # nil => viewed/burned/expired
next unless s
{ receipt: r, secret: s }
end

puts "Live, unviewed incoming secrets to re-notify: #{candidates.size}"
candidates.each do |c|
r, s = c[:receipt], c[:secret]
puts format(' %s created=%s to=%s domain=%s',
r.shortid,
Time.at(r.created.to_i).utc,
OT::Utils.obscure_email(r.recipients),
s.share_domain || 'canonical')
end

Verify the count and the recipients/timestamps look right. If the window is off, widen it and re-run — nothing is sent.

Step 2 — Send (flip the flag, re-enqueue via the real path)

Same block, but set DRY_RUN = false and add the enqueue at the end:

DRY_RUN = false

sent = 0
candidates.each do |c|
r, s = c[:receipt], c[:secret]
next if DRY_RUN

Onetime::Jobs::Publisher.enqueue_email(
:incoming_secret,
{
secret_key: s.identifier,
share_domain: s.share_domain,
recipient: r.recipients,
memo: r.memo,
has_passphrase: r.has_passphrase?,
locale: OT.default_locale, # original locale not stored on the receipt
},
domain_id: r.domain_id,
)
sent += 1
puts "re-enqueued #{r.shortid} -> #{OT::Utils.obscure_email(r.recipients)}"
end
puts "Re-enqueued #{sent} notifications"

This pushes them onto email.message.send; the workers deliver them — watch them drain:

podman exec <container> bin/ots queue status

Notes

- The payload mirrors create_incoming_secret.rb:292 exactly, with two substitutions: secret_key/share_domain come from the reloaded secret, and locale falls back to OT.default_locale because the original request locale isn't persisted on the receipt (recipients get the default-language email — cosmetic only).
- If instances scoring turns out not to be created, the dry-run's printed created= timestamps will look wrong (outside your window) — that's your signal to tell me and I'll switch the enumerator to expiration_timeline ranged by created + ttl instead.
