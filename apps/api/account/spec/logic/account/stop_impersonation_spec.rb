# apps/api/account/spec/logic/account/stop_impersonation_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'
require 'auth/operations/customers/stop_impersonation'

# The stop endpoint's authorization is the interesting part, because it is the
# one place in the feature that must NOT trust `cust`: during an impersonation
# `cust` is the target customer, so the check runs against the session
# PRINCIPAL instead. Everything that is not a verified colonel with a live
# marker gets a 404 — never a 403, which would advertise the endpoint.
RSpec.describe AccountAPI::Logic::Account::StopImpersonation do
  let(:now) { 1_756_700_000 }

  let(:target) do
    instance_double(Onetime::Customer,
      extid: 'ur_target', email: 'alice@example.com',
      anonymous?: false, suspended?: false)
  end

  let(:principal) do
    instance_double(Onetime::Customer,
      extid: 'ur_colonel', email: 'ops@example.com',
      role: 'colonel', verified?: true)
  end

  let(:session) { { 'external_id' => 'ur_colonel', 'role' => 'colonel' } }

  # cust is the TARGET, exactly as the auth strategy resolves it mid-overlay.
  let(:strategy_result) do
    double('StrategyResult', session: session, user: target,
      auth_method: 'sessionauth', metadata: {}, verified?: true)
  end

  let(:marker) do
    {
      'id' => 'imp_deadbeefdeadbeef',
      'target_extid' => 'ur_target',
      'target_email' => 'alice@example.com',
      'reason' => 'ticket #123',
      'started_at' => now,
      'expires_at' => now + Onetime::SessionImpersonation::TTL,
    }
  end

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(principal).to receive(:role?).with('colonel').and_return(true)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_colonel').and_return(principal)
    session[Onetime::SessionImpersonation::SESSION_KEY] = marker
  end

  def logic
    described_class.new(strategy_result, {})
  end

  describe 'the happy path' do
    it 'stops the impersonation and names the console page to return to' do
      subject = logic
      subject.raise_concerns

      expect(subject.process[:record]).to eq(
        stopped: true,
        target_extid: 'ur_target',
        redirect: '/colonel/customers/ur_target',
      )
    end

    it 'clears the marker' do
      subject = logic
      subject.raise_concerns
      subject.process

      expect(session).not_to have_key(Onetime::SessionImpersonation::SESSION_KEY)
    end

    # has_role? answers from this cache without loading a Customer.
    it 'restores the cached session role from the principal' do
      session['role'] = 'customer'

      subject = logic
      subject.raise_concerns
      subject.process

      expect(session['role']).to eq('colonel')
    end

    it 'records the stop event once' do
      subject = logic
      subject.raise_concerns
      subject.process

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'customer.impersonate.stop', actor: 'ur_colonel', target: 'ur_target'),
      )
    end
  end

  describe '404, not 403' do
    it 'hides the endpoint from a session with no marker' do
      session.delete(Onetime::SessionImpersonation::SESSION_KEY)

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'hides the endpoint when the principal is no longer a colonel' do
      allow(principal).to receive(:role?).with('colonel').and_return(false)

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'hides the endpoint when the principal is unverified' do
      allow(principal).to receive(:verified?).and_return(false)

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'hides the endpoint when the principal cannot be loaded' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_colonel').and_return(nil)

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'hides the endpoint when the session carries no principal' do
      session.delete('external_id')

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    # An expired marker is ended (and audited) by the read itself, then 404s.
    it 'hides the endpoint once the marker has expired' do
      allow(Familia).to receive(:now).and_return(now + Onetime::SessionImpersonation::TTL + 1)

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: hash_including(ended_by: 'expired')),
      )
    end
  end

  describe 'input surface' do
    # No impersonation_id parameter: the session IS the argument, so there is
    # nothing for a caller to aim at somebody else's impersonation.
    it 'takes no parameters' do
      subject = described_class.new(strategy_result, { 'impersonation_id' => 'imp_other' })
      subject.process_params
      subject.raise_concerns

      expect(subject.process[:record][:target_extid]).to eq('ur_target')
    end
  end
end
