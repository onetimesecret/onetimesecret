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
require 'onetime/operations/email/add_suppression'
require 'onetime/operations/email/remove_suppression'
require 'onetime/operations/ratelimit/registry'
require 'onetime/operations/ratelimit/inspect'
require 'onetime/operations/ratelimit/reset'

AE = Onetime::ColonelAuditEvent

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

## the registry knows the canonical limiter kinds, in registry order
Onetime::Operations::RateLimit::Registry.kinds
#=> ["feedback", "passphrase", "invite", "login", "reset_request_ip", "reset_request_email", "create_account_ip", "dns", "create_secret"]

## keys_for expands the templates byte-identically to the CLI's emitted keys
Onetime::Operations::RateLimit::Registry.keys_for('feedback', '1.2.3.4')
#=> ["feedback:submissions:1.2.3.4", "feedback:locked:1.2.3.4"]

## the reset-request IP tier derives the keys ResetRequestRateLimiter writes,
## so a deployment-wide IP lockout is clearable by the operator tooling
Onetime::Operations::RateLimit::Registry.keys_for('reset_request_ip', '203.0.113.0')
#=> ["reset_request:attempts:ip:203.0.113.0", "reset_request:locked:ip:203.0.113.0"]

## the reset-request email backstop derives its own pair from the same subject
Onetime::Operations::RateLimit::Registry.keys_for('reset_request_email', 'user@example.com')
#=> ["reset_request:attempts:email:user@example.com", "reset_request:locked:email:user@example.com"]

## the anonymous secret-creation limiter (F-02) keys on the MASKED client IP
## — the stored form the limiter writes, so operator clears actually hit
Onetime::Operations::RateLimit::Registry.keys_for('create_secret', '203.0.113.0')
#=> ["create_secret:attempts:ip:203.0.113.0", "create_secret:locked:ip:203.0.113.0"]

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

## a no-op reset records NO audit event (nothing mutated, nothing REFUSED)
# The colonel adapter returns 200 / "No active rate-limit state to reset" for
# :not_set, so it is not an operator-visible failure — unlike UnbanIP's
# :not_found (a 404), which IS recorded as a refusal.
AE.count
#=> 0

# ---- RateLimit::Reset: an unknown kind RAISES, and is audited ---------
#
# The Onetime::AuditedFailure mechanism: the success record sits after the
# SCAN + DEL, so a reset that blew up left no trace of the attempt.

## an unknown limiter kind raises ArgumentError
AE.events.clear
begin
  Onetime::Operations::RateLimit::Reset.new(kind: 'bogus', subject: '9.9.9.9', actor: @actor).call
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## the raise recorded ONE result: :failure event with the unchanged verb/target shape
@rl_ev = AE.recent(1).first
[AE.count, @rl_ev['verb'], @rl_ev['target'], @rl_ev['result'], @rl_ev['detail']['error']]
#=> [1, "ratelimit.reset", "bogus:9.9.9.9", "failure", "ArgumentError"]

# ---- Email::SendTest: a delivery failure is audited, then re-raised ---

## a send whose backend blows up re-raises the original error
AE.events.clear
@backend = Onetime::Mail::Mailer.delivery_backend
@backend.define_singleton_method(:deliver) { |*| raise(Onetime::Problem, 'smtp refused') }
begin
  Onetime::Operations::Email::SendTest.new(to: 'ops@example.com', actor: @actor).call
  :no_raise
rescue Onetime::Problem
  :raised
ensure
  @backend.singleton_class.remove_method(:deliver)
end
#=> :raised

## the failed send recorded ONE result: :failure event targeting the recipient
@st_ev = AE.recent(1).first
[AE.count, @st_ev['verb'], @st_ev['target'], @st_ev['result'], @st_ev['detail']['dry_run']]
#=> [1, "email.test_send", "ops@example.com", "failure", false]

# ---- Email suppression refusals --------------------------------------

## removing an address that is not suppressed is a REFUSED mutation (404 at the adapter)
AE.events.clear
@rm = Onetime::Operations::Email::RemoveSuppression.new(
  address: "never-suppressed-#{SecureRandom.hex(4)}@example.com", actor: @actor,
).call
@rm_ev = AE.recent(1).first
[@rm.status, AE.count, @rm_ev['verb'], @rm_ev['result'], @rm_ev['detail']['reason']]
#=> [:not_found, 1, "email.suppression_remove", "failure", 'not_found']

## a blank-address suppress is a REFUSED mutation, not a silent no-op
AE.events.clear
@blank = Onetime::Operations::Email::AddSuppression.new(address: '  ', actor: @actor).call
@bl_ev = AE.recent(1).first
[@blank.status, AE.count, @bl_ev['verb'], @bl_ev['result'], @bl_ev['detail']['reason']]
#=> [nil, 1, "email.suppress", "failure", 'blank_address']

# Cleanup
@db.del('feedback:submissions:9.9.9.9', 'feedback:locked:9.9.9.9')
AE.events.clear
