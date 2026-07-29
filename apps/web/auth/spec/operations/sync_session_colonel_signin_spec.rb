# apps/web/auth/spec/operations/sync_session_colonel_signin_spec.rb
#
# frozen_string_literal: true

# Unit tests for the colonel.signin audit event emitted by
# Auth::Operations::SyncSession (the FULL-auth-mode session-establishment site).
#
# Colonel session establishment was invisible in the audit trail. Nearly all
# colonel activity is reads, and reads never audit by design (CONTRACT 4), so
# the audit screen read empty even while operators were in the console daily.
#
# These examples drive #record_colonel_signin directly rather than a full #call:
# the surrounding op needs the auth database, and what needs pinning here is the
# gate (colonel only), the exact verb, and the public-identity contract.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/sync_session_colonel_signin_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'auth/operations/sync_session'

RSpec.describe Auth::Operations::SyncSession do
  let(:account) { { email: 'colonel@example.com', external_id: 'ur_colonel', status_id: 2 } }
  let(:session) { { 'auth_method' => 'password' } }
  let(:request) { double('Request', ip: '203.0.113.7', user_agent: 'rspec') }
  let(:db) { double('Sequel::Database') }

  let(:colonel) do
    double('Customer', extid: 'ur_colonel', custid: 'colonel@example.com', role: 'colonel')
  end

  let(:plain_customer) do
    double('Customer', extid: 'ur_plain', custid: 'user@example.com', role: 'customer')
  end

  let(:op) do
    described_class.new(
      account: account,
      account_id: 42,
      session: session,
      request: request,
      correlation_id: 'corr_1',
      db: db,
    )
  end

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    allow(Auth::Logging).to receive(:log_error)
  end

  it 'records colonel.signin with the acting colonel as actor and target' do
    op.send(:record_colonel_signin, colonel)

    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
      actor: 'ur_colonel',
      verb: 'colonel.signin',
      target: 'ur_colonel',
      result: :success,
      detail: { auth_method: 'password', ip: '203.0.113.7' },
    )
  end

  it 'uses the single-sourced verb constant (both auth modes must agree)' do
    expect(Onetime::AdminAuditEvent::VERB_COLONEL_SIGNIN).to eq('colonel.signin')
  end

  it 'records NOTHING for a non-colonel login (CONTRACT 4: not an admin action)' do
    op.send(:record_colonel_signin, plain_customer)

    expect(Onetime::AdminAuditEvent).not_to have_received(:record)
  end

  it 'never fails a login because the audit event could not be assembled' do
    exploding = double('Customer', role: 'colonel')
    allow(exploding).to receive(:extid).and_raise(StandardError, 'boom')

    expect { op.send(:record_colonel_signin, exploding) }.not_to raise_error
    expect(Auth::Logging).to have_received(:log_error)
      .with(:colonel_signin_audit_failed, hash_including(account_id: 42))
  end
end
