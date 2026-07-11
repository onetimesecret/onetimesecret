# try/unit/mail/emails_sent_counter_try.rb
#
# frozen_string_literal: true

# Tests for the global `emails_sent` counter maintained at the mail send
# chokepoint (Onetime::Mail::Delivery::Base#deliver). Part of the colonel admin
# rebuild backend-debt fix (issue #3653, debt §7): the colonel stats dashboard
# reports `emails_sent`, which was previously stubbed to 0. Delivery::Base is the
# single point every backend's successful send converges on, so it increments the
# global `Onetime::Customer.emails_sent` counter exactly once per delivered email.
#
# Covers:
# - a real provider send (delivery_log_status == 'sent') increments the counter
# - the Logger backend ('logged') does NOT increment (no real email leaves)
# - the Disabled backend ('skipped') does NOT increment (no real email leaves)
# - deliver returns the backend result on the counted path
# - the increment is best-effort: a counter write failure never breaks delivery

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/mail'

# A minimal backend that behaves like a real provider: perform_delivery
# succeeds and delivery_log_status inherits Base's default of 'sent'.
class SentTestBackend < Onetime::Mail::Delivery::Base
  def perform_delivery(_email)
    { status: 'ok' }
  end
end

@email = {
  to: 'recipient@test.com',
  from: 'sender@test.com',
  subject: 'Counter Test',
  text_body: 'Body',
}

# TRYOUTS

## Base default delivery_log_status is 'sent' (real provider send)
SentTestBackend.new({}).delivery_log_status
#=> 'sent'

## A real provider send increments the global emails_sent counter by exactly 1
before = Onetime::Customer.emails_sent.to_i
SentTestBackend.new({}).deliver(@email)
Onetime::Customer.emails_sent.to_i - before
#=> 1

## deliver still returns the backend result on the counted path
SentTestBackend.new({}).deliver(@email)
#=> { status: 'ok' }

## The Logger backend ('logged') does NOT increment — no real email is sent
before = Onetime::Customer.emails_sent.to_i
Onetime::Mail::Delivery::Logger.new({}).deliver(@email)
Onetime::Customer.emails_sent.to_i - before
#=> 0

## The Disabled backend ('skipped') does NOT increment — delivery is a no-op
before = Onetime::Customer.emails_sent.to_i
Onetime::Mail::Delivery::Disabled.new({}).deliver(@email)
Onetime::Customer.emails_sent.to_i - before
#=> 0

## Best-effort: a counter write failure is swallowed and delivery still succeeds
# Force the counter accessor to raise (simulating Redis being unavailable), then
# confirm deliver returns the backend result rather than propagating the error.
# The original accessor is aliased and restored so global state is left intact.
@sc = Onetime::Customer.singleton_class
@sc.send(:alias_method, :__orig_emails_sent, :emails_sent)
Onetime::Customer.define_singleton_method(:emails_sent) { raise 'redis unavailable' }
begin
  @result = SentTestBackend.new({}).deliver(@email)
ensure
  @sc.send(:alias_method, :emails_sent, :__orig_emails_sent)
  @sc.send(:remove_method, :__orig_emails_sent)
end
@result
#=> { status: 'ok' }

## The counter accessor is restored and normal counting resumes after the failure
before = Onetime::Customer.emails_sent.to_i
SentTestBackend.new({}).deliver(@email)
Onetime::Customer.emails_sent.to_i - before
#=> 1
