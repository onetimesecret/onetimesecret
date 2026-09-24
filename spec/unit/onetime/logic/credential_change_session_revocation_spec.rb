# spec/unit/onetime/logic/credential_change_session_revocation_spec.rb
#
# frozen_string_literal: true

# Pins the kwarg shape the simple-mode credential-change mixin hands to
# RevokeAllForCustomerExceptCurrent: the resolved `customer:` record, never a
# `custid:` the op would re-resolve through the extid index. A miss there
# (#4205/#4217 drift) takes the op's nil-customer branch — a silent
# `blobs_deleted: 0` success with every pre-change session blob still live,
# the exact M-2 outcome this mixin exists to prevent. The live-datastore proof
# of that gap is in
# try/unit/operations/sessions/revoke_all_for_customer_except_current_try.rb;
# the end-to-end simple-mode paths that include this mixin are covered by
# try/unit/logic/account/update_password_try.rb and
# try/unit/logic/authentication/reset_password_try.rb.
#
# The async sweep is deliberately still enqueued BY EXTID: the publisher is the
# queue API and only ever carries an identifier, so that call is not a
# re-resolution the mixin can avoid — the inline revoke is.
#
# Run: pnpm run test:rspec spec/unit/onetime/logic/credential_change_session_revocation_spec.rb

require 'spec_helper'
require 'onetime/logic/credential_change_session_revocation'

RSpec.describe Onetime::Logic::CredentialChangeSessionRevocation do
  # Minimal host: the mixin's contract is `#auth_logger` plus a class name
  # for its failure-path tags. The entry point is private in production
  # (mixed into UpdatePassword / ResetPassword), so expose it here.
  let(:host_class) do
    Class.new do
      include Onetime::Logic::CredentialChangeSessionRevocation

      def self.name
        'CredentialChangeHost'
      end

      attr_reader :auth_logger

      def initialize(auth_logger)
        @auth_logger = auth_logger
      end

      def run(customer, except_session_id: nil)
        revoke_sessions_for_credential_change(customer, except_session_id: except_session_id)
      end
    end
  end

  let(:auth_logger) { double('auth_logger', info: nil, error: nil) }
  let(:host) { host_class.new(auth_logger) }

  let(:customer) do
    instance_double(Onetime::Customer, extid: 'ur_cred', last_password_update!: nil)
  end

  let(:current_sid) { 'a' * 64 }

  let(:revoke_op) { Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent }

  let(:op) do
    instance_double(
      revoke_op,
      call: revoke_op::Result.new(
        revoked: true, blobs_deleted: 2, untracked_deleted: 0, scan_capped: false,
      ),
    )
  end

  before do
    allow(revoke_op).to receive(:new).and_return(op)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_session_revocation_sweep).and_return(true)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email)
    allow(Onetime::Customer).to receive(:load)
    allow(Onetime::Customer).to receive(:find_by_extid)
    allow(Onetime::Customer).to receive(:find_by_email)
  end

  it 'hands the inline revoke the record it holds, never a re-resolvable extid' do
    host.run(customer, except_session_id: current_sid)

    expect(revoke_op).to have_received(:new).once
    expect(revoke_op).to have_received(:new).with(
      hash_including(customer: customer, except_session_id: current_sid, scan_untracked: false),
    )
    expect(revoke_op).not_to have_received(:new).with(hash_including(:custid))
    expect(op).to have_received(:call)

    # The mixin itself never goes back to the index for a record it already has.
    expect(Onetime::Customer).not_to have_received(:load_by_extid_or_email)
    expect(Onetime::Customer).not_to have_received(:load)
    expect(Onetime::Customer).not_to have_received(:find_by_extid)
    expect(Onetime::Customer).not_to have_received(:find_by_email)
  end

  it 'passes a nil except_session_id through for the reset path (revoke ALL), still by record' do
    host.run(customer)

    expect(revoke_op).to have_received(:new).with(
      hash_including(customer: customer, except_session_id: nil, scan_untracked: false),
    )
    expect(revoke_op).not_to have_received(:new).with(hash_including(:custid))
  end

  it 'enqueues the async sweep by extid (the queue API carries an identifier, not a record)' do
    host.run(customer, except_session_id: current_sid)

    expect(Onetime::Jobs::Publisher).to have_received(:enqueue_session_revocation_sweep)
      .with('ur_cred', except_session_id: current_sid)
  end

  it 'still revokes inline (by record) when the sweep enqueue raises' do
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_session_revocation_sweep)
      .and_raise(StandardError, 'broker down')

    host.run(customer, except_session_id: current_sid)

    expect(auth_logger).to have_received(:error)
      .with('[credential-change] sessions_sweep_enqueue_FAILED', hash_including(customer_id: 'ur_cred'))
    expect(revoke_op).to have_received(:new).with(hash_including(customer: customer))
    expect(op).to have_received(:call)
  end
end
