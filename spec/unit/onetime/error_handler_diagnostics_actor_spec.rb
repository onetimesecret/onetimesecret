# spec/unit/onetime/error_handler_diagnostics_actor_spec.rb
#
# frozen_string_literal: true

# Pseudonymous "users affected" attribution on BACKEND Sentry events.
#
# Why this exists: Sentry derives its affected-user count from event.user.id
# and from nothing else. No backend capture site set one, so every Ruby-side
# issue in production read as zero affected users regardless of how many
# accounts it actually hit — an operator could not tell "one account is
# broken" from "every account is broken".
#
# The fix cannot be "send the email". Sentry's user object is not exempt from
# the diagnostics boundary; an id set there is also a searchable field. So the
# id is always a DiagnosticsRef: opaque, keyed, one-way — and its pre-image is
# the customer EXTID, never the email
# (docs/specs/diagnostics/actor-ref-preimage-debate-decision.md).
#
# The properties pinned below are the ones whose failure modes are silent:
#
#   1. The id IS the ref. Not a truncation of it, not something else that
#      happens to look opaque.
#   2. A candidate that is not positively an extid is REFUSED. DiagnosticsRef
#      digests whatever string it is handed, so a bare-string fallback here is
#      how an `email:` caller ends up with an email hashed under the
#      diagnostics key. Refusal is what makes that unrepresentable.
#   3. Neither the email NOR the extid appears anywhere in the serialized
#      event. Asserted against a real Sentry::ErrorEvent payload rather than
#      against the scope object, because it is the serialized form that leaves
#      the process — and under the extid derivation the extid is the sensitive
#      pre-image, so forwarding it would hand Sentry both the ref and its input.
#   4. Anonymous sets NO user. Not `{id: nil}` and not a placeholder — either
#      one merges every anonymous visitor into a single "affected user" and
#      makes the count wrong in the other direction.
#   5. A derivation failure still captures the EVENT. Attribution is a nice to
#      have; the exception report is not. Losing the first to save the second
#      is the correct trade and it must be executed, not assumed.
#
# Run with:
#   tests/lanes/run unit --only spec/unit/onetime/error_handler_diagnostics_actor_spec.rb
require 'spec_helper'
require 'sentry-ruby'

RSpec.describe Onetime::ErrorHandler do
  # Shaped like a real Customer extid: Familia's external_identifier feature
  # under `format: 'ur%{id}'` emits `ur` plus 25 base36 characters.
  let(:extid) { 'ur00fedcba9876543210zyxwvu' }
  let(:email) { 'affected.person@example.com' }

  # Pin a known keying rather than inheriting whatever the lane exports, so an
  # unpinned lane cannot make every example here assert against nil and pass
  # for the wrong reason.
  let(:keying) { 'a-known-diagnostics-key' }

  let(:expected_ref) { Onetime::Utils::DiagnosticsRef.actor_ref(extid) }

  let(:customer) do
    instance_double(Onetime::Customer, extid: extid, anonymous?: false)
  end

  before do
    allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(keying)
  end

  describe '.diagnostics_actor' do
    it 'returns the DiagnosticsRef as the id, for a customer' do
      expect(described_class.diagnostics_actor(customer)).to eq({ id: expected_ref })
    end

    it 'returns the same id for a bare extid string' do
      expect(described_class.diagnostics_actor(extid)).to eq({ id: expected_ref })
    end

    it 'derives from the extid, not from anything else the customer carries' do
      # The customer double answers ONLY #extid and #anonymous?. A verifying
      # double raises on any other message, so this passing is itself the proof
      # that no other attribute is consulted.
      expect(described_class.diagnostics_actor(customer)[:id])
        .to eq(Onetime::Utils::DiagnosticsRef.actor_ref(extid))
    end

    it 'emits a 16-char opaque hex id, never the extid' do
      user = described_class.diagnostics_actor(customer)

      expect(user[:id]).to match(/\A[0-9a-f]{16}\z/)
      expect(user[:id]).not_to eq(extid)
      expect(user[:id]).not_to include('ur00')
    end

    it 'carries no key other than :id' do
      # An email/username/ip_address key here would be sent verbatim by the
      # SDK. The absence is the contract, so it is asserted, not assumed.
      expect(described_class.diagnostics_actor(customer).keys).to eq([:id])
    end

    # The bare-string candidate API is dead ON PURPOSE. Every rejection below
    # would otherwise be silently hashed under the diagnostics key and become a
    # searchable Sentry field's pre-image.
    context 'a candidate that is not positively an extid' do
      it 'refuses a bare email string rather than hashing it' do
        expect(described_class.diagnostics_actor(email)).to be_nil
      end

      it 'refuses an email even when it is the only thing a customer offers' do
        emailish = instance_double(Onetime::Customer, anonymous?: false)
        expect(described_class.diagnostics_actor(emailish)).to be_nil
      end

      it 'refuses a custid' do
        expect(described_class.diagnostics_actor('cust-1234567890')).to be_nil
      end

      it 'refuses an objid' do
        expect(described_class.diagnostics_actor('01JCUSTABCDEFGHJKMNPQRSTVW')).to be_nil
      end

      it 'refuses an organization-shaped or otherwise foreign prefix' do
        expect(described_class.diagnostics_actor('org00fedcba9876543210zyxwv')).to be_nil
      end

      it 'refuses arbitrary garbage' do
        ['ur', 'UR00FEDCBA9876543210ZYXWVU', 'ur_00fedcba', '  ', 'null', '42'].each do |garbage|
          expect(described_class.diagnostics_actor(garbage)).to(
            be_nil, "expected #{garbage.inspect} to be refused"
          )
        end
      end
    end

    context 'anonymous' do
      it 'returns nil for nil' do
        expect(described_class.diagnostics_actor(nil)).to be_nil
      end

      it 'returns nil for an anonymous customer' do
        anon = instance_double(Onetime::Customer, anonymous?: true)
        expect(described_class.diagnostics_actor(anon)).to be_nil
      end

      it 'returns nil for a customer with no extid yet' do
        fresh = instance_double(Onetime::Customer, extid: nil, anonymous?: false)
        expect(described_class.diagnostics_actor(fresh)).to be_nil
      end
    end

    context 'when the deployment has no usable keying secret' do
      before do
        allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(nil)
      end

      it 'returns nil rather than an unkeyed or partial user' do
        expect(described_class.diagnostics_actor(customer)).to be_nil
      end
    end

    context 'when ref derivation raises' do
      before do
        allow(Onetime::Utils::DiagnosticsRef)
          .to receive(:actor_ref).and_raise(StandardError, 'derivation exploded')
      end

      it 'swallows the failure and returns nil' do
        expect { described_class.diagnostics_actor(customer) }.not_to raise_error
        expect(described_class.diagnostics_actor(customer)).to be_nil
      end
    end
  end

  describe '.set_diagnostics_actor' do
    let(:scope) { Sentry::Scope.new }

    it 'sets the ref as the Sentry user and reports true' do
      expect(described_class.set_diagnostics_actor(scope, customer)).to be(true)
      expect(scope.user).to eq({ id: expected_ref })
    end

    it 'leaves the scope userless for anonymous and reports false' do
      expect(described_class.set_diagnostics_actor(scope, nil)).to be(false)
      expect(scope.user).to be_empty
    end

    it 'leaves the scope userless for an email candidate' do
      expect(described_class.set_diagnostics_actor(scope, email)).to be(false)
      expect(scope.user).to be_empty
    end

    it 'never writes { id: nil } when derivation declines' do
      allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(nil)

      described_class.set_diagnostics_actor(scope, customer)

      expect(scope.user).to be_empty
      expect(scope.user).not_to have_key(:id)
    end

    it 'does not raise when derivation fails' do
      allow(Onetime::Utils::DiagnosticsRef)
        .to receive(:actor_ref).and_raise(StandardError, 'derivation exploded')

      expect(described_class.set_diagnostics_actor(scope, customer)).to be(false)
      expect(scope.user).to be_empty
    end
  end

  # The scope object is not what leaves the process. These examples run the
  # real Sentry serialization path (Scope#apply_to_event -> Event#to_h) so the
  # leak assertion is made against the payload an operator would actually see.
  describe 'the serialized event payload' do
    let(:configuration) do
      Sentry::Configuration.new.tap { |config| config.dsn = 'http://public@localhost:5000/1' }
    end

    def payload_for(candidate)
      scope = Sentry::Scope.new
      described_class.set_diagnostics_actor(scope, candidate)
      scope.set_context('error_handler', { operation: 'send_password_changed_email' })

      event = Sentry::ErrorEvent.new(configuration: configuration)
      scope.apply_to_event(event)
      event.to_h
    end

    it 'carries the ref as user.id' do
      expect(payload_for(customer)[:user]).to eq({ id: expected_ref })
    end

    it 'contains neither the email nor the extid anywhere at all' do
      serialized = payload_for(customer).inspect

      expect(serialized).not_to include(email)
      expect(serialized).not_to include('affected.person')
      # The local part alone is enough to identify; assert on the domain too so
      # a future partial-redaction regression cannot pass this example.
      expect(serialized).not_to include('example.com')
      # The extid is the PRE-IMAGE under this derivation. Shipping it alongside
      # the ref would hand Sentry the input and the output together.
      expect(serialized).not_to include(extid)
      expect(serialized).to include(expected_ref)
    end

    it 'omits the user key entirely for an anonymous capture' do
      payload = payload_for(nil)

      expect(payload[:user]).to be_nil.or be_empty
    end
  end

  describe '.capture_error' do
    let(:exception) { StandardError.new('boom') }
    let(:scope) { Sentry::Scope.new }

    before do
      allow(described_class).to receive(:app_logger).and_return(double('Logger', debug: nil, error: nil))
      stub_const('Sentry', Module.new) unless defined?(Sentry)
      allow(Sentry).to receive(:capture_exception) do |_ex, &block|
        block&.call(scope)
        'event-id-1'
      end
    end

    def capture(context)
      described_class.send(:capture_error, 'password_changed_email', exception, context)
    end

    def forwarded_context(context)
      captured = nil
      allow(scope).to receive(:set_context) do |key, value|
        captured = value if key == 'error_handler'
      end
      capture(context)
      captured
    end

    # Every key a hook uses to carry an extid is both a SUBJECT and a SCRUB
    # target. Subject, because attribution is the point; scrub, because the
    # extid is the pre-image and must not travel beside the ref it produced.
    {
      external_id: 'the canonical key',
      extid: 'the account-hook alias',
      customer_id: 'the extid-valued alias',
    }.each do |key, description|
      context "when the context carries #{key} (#{description})" do
        it 'sets the pseudonymous user from it' do
          capture({ account_id: 42, key => extid })

          expect(scope.user).to eq({ id: expected_ref })
        end

        it 'CONSUMES it rather than forwarding it into the Sentry context' do
          captured = forwarded_context({ account_id: 42, key => extid })

          expect(captured).to eq({ operation: 'password_changed_email', account_id: 42 })
          expect(captured.inspect).not_to include(extid)
        end
      end
    end

    [:cust, :customer].each do |key|
      context "when the context carries a customer object under #{key}" do
        it 'sets the pseudonymous user from its extid' do
          capture({ account_id: 42, key => customer })

          expect(scope.user).to eq({ id: expected_ref })
        end

        it 'CONSUMES the object rather than forwarding it' do
          captured = forwarded_context({ account_id: 42, key => customer })

          expect(captured).to eq({ operation: 'password_changed_email', account_id: 42 })
        end
      end
    end

    # An email is scrubbed but is NOT a subject: nothing is derivable from it
    # any more, and accepting one as a candidate is exactly how an email gets
    # hashed under the diagnostics key.
    it 'scrubs an email without deriving a user from it' do
      captured = forwarded_context({ account_id: 42, email: email })

      expect(scope.user).to be_empty
      expect(captured).to eq({ operation: 'password_changed_email', account_id: 42 })
      expect(captured.inspect).not_to include(email)
    end

    it 'sets no user when the context names no subject' do
      capture({ account_id: 42 })

      expect(scope.user).to be_empty
    end

    it 'still captures the event when ref derivation raises' do
      allow(Onetime::Utils::DiagnosticsRef)
        .to receive(:actor_ref).and_raise(StandardError, 'derivation exploded')

      expect(Sentry).to receive(:capture_exception).and_return('event-id-1')

      expect { capture({ account_id: 42, external_id: extid }) }.not_to raise_error
    end
  end
end
