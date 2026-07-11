# try/unit/operations/email_ratelimit_tools_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted email + rate-limit tools operations (ticket #44):
#   Onetime::Operations::Email::{ListTemplates, PreviewTemplate, SendTest}
#   Onetime::Operations::RateLimit::{Registry, Inspect, Reset}
#
# These are the SINGLE implementation of each verb (the colonel API + `bin/ots
# email` / `bin/ots ratelimit` CLI are thin adapters). Covers:
# - ListTemplates: enumerates the canonical templates with their formats (read)
# - PreviewTemplate: renders sample text/html with NO side effects (read, no audit)
# - PreviewTemplate: unknown template raises, missing sample raises MissingSampleError
# - SendTest.build: byte-identical brand-aware diagnostic (CLI golden-master)
# - SendTest dry-run: sends nothing, records NO audit
# - SendTest live: delivers via the logger backend, records EXACTLY ONE audit event
# - RateLimit::Registry: CLI-golden key derivation is byte-identical
# - RateLimit::Inspect: reads TTL/value for the bounded key set (read, no audit)
# - RateLimit::Reset: deletes keys + records ONE audit; idempotent no-op records none
#
# Run: try --agent try/unit/operations/email_ratelimit_tools_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/email/list_templates'
require 'onetime/operations/email/preview_template'
require 'onetime/operations/email/send_test'
require 'onetime/operations/ratelimit/registry'
require 'onetime/operations/ratelimit/inspect'
require 'onetime/operations/ratelimit/reset'

AE = Onetime::AdminAuditEvent

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid

AE.events.clear

# ---- Email::ListTemplates (read) --------------------------------------

## ListTemplates returns one entry per canonical template, in order
@templates = Onetime::Operations::Email::ListTemplates.new.call
@templates.map(&:name).first(3)
#=> ["secret_link", "welcome", "password_request"]

## every entry advertises at least one renderable format
@templates.all? { |e| e.formats.any? }
#=> true

## listing records NO audit event (read-only verb)
AE.count
#=> 0

# ---- Email::PreviewTemplate (read, no side effects) -------------------

## PreviewTemplate renders the text body from sample data
@preview = Onetime::Operations::Email::PreviewTemplate.new(template: 'secret_link').call
[@preview.format, @preview.body.is_a?(String) && !@preview.body.empty?]
#=> ["text", true]

## an HTML preview renders the HTML arm
@html = Onetime::Operations::Email::PreviewTemplate.new(template: 'secret_link', format: 'html').call
@html.format
#=> "html"

## previewing records NO audit event (read-only, no dispatch)
AE.count
#=> 0

## an unknown template with supplied data raises ArgumentError (unknown class)
# (data is supplied so we skip sample loading and reach template_class_for, which
# is the CLI's order: load_data then resolve_template.)
begin
  Onetime::Operations::Email::PreviewTemplate.new(template: 'does_not_exist', data: { foo: 'bar' }).call
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## an unknown template with NO data raises MissingSampleError first (CLI parity:
## load_data runs before resolve_template, so the missing sample is hit first)
begin
  Onetime::Operations::Email::PreviewTemplate.new(template: 'does_not_exist').call
  :no_raise
rescue Onetime::Operations::Email::PreviewTemplate::MissingSampleError
  :missing_sample
end
#=> :missing_sample

# ---- Email::SendTest.build (CLI golden-master parity) -----------------

## build produces a brand-aware subject + body with the provider/host probe
@diag = Onetime::Operations::Email::SendTest.build(to: 'ops@example.com')
[@diag.to, @diag.subject.start_with?('['), @diag.text_body.include?('Provider:'), @diag.provider]
#=> ["ops@example.com", true, true, "logger"]

## the body is byte-identical to the pre-extraction CLI literal
@expected_body = "This is a test email from the #{@diag.subject[/\[(.*?)\]/, 1]} CLI.\n\nProvider: #{@diag.provider}\nTimestamp: #{@diag.timestamp}\nHost: #{@diag.host}"
@diag.text_body == @expected_body
#=> true

# ---- Email::SendTest dry-run (no send, no audit) ----------------------

## a dry-run returns :dry_run and dispatches nothing
AE.events.clear
@dry = Onetime::Operations::Email::SendTest.new(to: 'ops@example.com', actor: @actor, dry_run: true).call
@dry.status
#=> :dry_run

## a dry-run records NO audit event
AE.count
#=> 0

# ---- Email::SendTest live (logger backend, one audit) -----------------

## a real send returns :sent (test env uses the logger delivery backend)
AE.events.clear
@sent = Onetime::Operations::Email::SendTest.new(to: 'ops@example.com', actor: @actor, dry_run: false).call
@sent.status
#=> :sent

## exactly ONE audit event was recorded for the send
AE.count
#=> 1

## the audit event is the test_send verb, targeting the recipient, actored by PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["email.test_send", "ops@example.com", "ur1colonelpub"]

# ---- RateLimit::Registry (CLI golden-master key derivation) -----------

## the registry knows the four canonical limiter kinds
Onetime::Operations::RateLimit::Registry.kinds
#=> ["feedback", "passphrase", "invite", "dns"]

## keys_for expands the templates byte-identically to the CLI's emitted keys
Onetime::Operations::RateLimit::Registry.keys_for('feedback', '1.2.3.4')
#=> ["feedback:submissions:1.2.3.4", "feedback:locked:1.2.3.4"]

## an unknown kind yields nil (the CLI prints its "Unknown" branch)
Onetime::Operations::RateLimit::Registry.keys_for('nope', 'x')
#=> nil

# ---- RateLimit::Inspect (read) ----------------------------------------

## seed a feedback counter, then inspect it (read-only)
@db = Onetime::Feedback.dbclient
@db.del('feedback:submissions:9.9.9.9', 'feedback:locked:9.9.9.9')
@db.setex('feedback:submissions:9.9.9.9', 600, '3')
AE.events.clear
@insp = Onetime::Operations::RateLimit::Inspect.new(kind: 'feedback', subject: '9.9.9.9').call
@sub_entry = @insp.entries.find { |e| e.key == 'feedback:submissions:9.9.9.9' }
[@sub_entry.value, @sub_entry.exists, @sub_entry.ttl.positive?]
#=> ["3", true, true]

## inspecting records NO audit event (read-only verb)
AE.count
#=> 0

# ---- RateLimit::Reset (mutating, one audit) ---------------------------

## resetting an active limiter deletes the key(s) and returns :success
AE.events.clear
@reset = Onetime::Operations::RateLimit::Reset.new(kind: 'feedback', subject: '9.9.9.9', actor: @actor).call
[@reset.status, @db.get('feedback:submissions:9.9.9.9').nil?]
#=> [:success, true]

## exactly ONE audit event was recorded for the reset
AE.count
#=> 1

## the audit event is the reset verb targeting kind:subject, actored by PUBLIC id
@rev = AE.recent(1).first
[@rev['verb'], @rev['target'], @rev['actor']]
#=> ["ratelimit.reset", "feedback:9.9.9.9", "ur1colonelpub"]

## resetting an already-clear subject is an idempotent no-op (:not_set)
AE.events.clear
@noop = Onetime::Operations::RateLimit::Reset.new(kind: 'feedback', subject: '9.9.9.9', actor: @actor).call
@noop.status
#=> :not_set

## a no-op reset records NO audit event (nothing mutated)
AE.count
#=> 0

# Cleanup
@db.del('feedback:submissions:9.9.9.9', 'feedback:locked:9.9.9.9')
AE.events.clear
