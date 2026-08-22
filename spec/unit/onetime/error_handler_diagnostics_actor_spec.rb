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
# id is always a DiagnosticsRef: opaque, keyed, one-way.
#
# The four properties pinned below are the ones whose failure modes are silent:
#
#   1. The id IS the ref. Not a truncation of it, not something else that
#      happens to look opaque.
#   2. The email appears NOWHERE in the serialized event. Asserted against a
#      real Sentry::ErrorEvent payload rather than against the scope object,
#      because it is the serialized form that leaves the process.
#   3. Anonymous sets NO user. Not `{id: nil}` and not a placeholder — either
#      one merges every anonymous visitor into a single "affected user" and
#      makes the count wrong in the other direction.
#   4. A derivation failure still captures the EVENT. Attribution is a nice to
#      have; the exception report is not. Losing the first to save the second
#      is the correct trade and it must be executed, not assumed.
#
# Run with:
#   tests/lanes/run unit --only spec/unit/onetime/error_handler_diagnostics_actor_spec.rb
require 'spec_helper'
require 'sentry-ruby'

RSpec.describe Onetime::ErrorHandler do
  let(:email) { 'affected.person@example.com' }

  # Pin a known keying rather than inheriting whatever the lane exports.
  # DiagnosticsRef refuses the shared federation secret when no residency
  # resolves, so an unpinned lane would make every example here assert against
  # nil and pass for the wrong reason.
  let(:keying) do
    Onetime::Utils::DiagnosticsRef::Keying.new(
      secret: 'a-known-diagnostics-key', scope: 'federated', residency: 'stub-region'
    )
  end

  let(:expected_ref) { Onetime::Utils::DiagnosticsRef.actor_ref(email) }

  let(:customer) do
    instance_double(Onetime::Customer, email: email, anonymous?: false)
  end

  before do
    allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(keying)
  end

  describe '.diagnostics_actor' do
    it 'returns the DiagnosticsRef as the id, for a customer' do
      expect(described_class.diagnostics_actor(customer)).to eq({ id: expected_ref })
    end

    it 'returns the same id for a bare email string' do
      expect(described_class.diagnostics_actor(email)).to eq({ id: expected_ref })
    end

    it 'emits a 16-char opaque hex id, never the email' do
      user = described_class.diagnostics_actor(customer)

      expect(user[:id]).to match(/\A[0-9a-f]{16}\z/)
      expect(user[:id]).not_to eq(email)
      expect(user[:id]).not_to include('affected')
      expect(user[:id]).not_to include('example.com')
    end

    it 'carries no key other than :id' do
      # An email/username/ip_address key here would be sent verbatim by the
      # SDK. The absence is the contract, so it is asserted, not assumed.
      expect(described_class.diagnostics_actor(customer).keys).to eq([:id])
    end

    context 'anonymous' do
      it 'returns nil for nil' do
        expect(described_class.diagnostics_actor(nil)).to be_nil
      end

      it 'returns nil for an anonymous customer' do
        anon = instance_double(Onetime::Customer, anonymous?: true)
        expect(described_class.diagnostics_actor(anon)).to be_nil
      end

      it 'returns nil for a blank email' do
        expect(described_class.diagnostics_actor('   ')).to be_nil
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

    it 'contains the email nowhere at all' do
      serialized = payload_for(customer).inspect

      expect(serialized).not_to include(email)
      expect(serialized).not_to include('affected.person')
      # The local part alone is enough to identify; assert on the domain too so
      # a future partial-redaction regression cannot pass this example.
      expect(serialized).not_to include('example.com')
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

    it 'sets the pseudonymous user when the context names the subject' do
      capture({ account_id: 42, email: email })

      expect(scope.user).to eq({ id: expected_ref })
    end

    it 'CONSUMES the email rather than forwarding it into the Sentry context' do
      captured = nil
      allow(scope).to receive(:set_context) do |key, value|
        captured = value if key == 'error_handler'
      end

      capture({ account_id: 42, email: email })

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

      expect { capture({ account_id: 42, email: email }) }.not_to raise_error
    end
  end
end
