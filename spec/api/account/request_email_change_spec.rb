# spec/api/account/request_email_change_spec.rb
#
# frozen_string_literal: true

require_relative '../../integration/integration_spec_helper'

# Regression coverage for two PR #3915 review findings on
# AccountAPI::Logic::Account::RequestEmailChange:
#
# 1. Quota-vs-durability ordering (item 3, P1): increment_request_count must
#    run only after the pending-change secret is durably saved. A Redis write
#    failure during secret creation must NOT consume the MAX_REQUESTS quota —
#    previously five flaky saves locked the user out for 24 hours with no
#    pending change ever created. Conversely, a failure AFTER the secret is
#    saved (e.g. email enqueue) must still count, since durable state exists.
#
# 2. Single password verification (item 5): field_specific_concerns and
#    valid_update? share one memoized verify_password result via
#    password_verified?, avoiding a second Rodauth valid_login_and_password?
#    DB round-trip per successful change request in full auth mode.
#
# Tests drive the logic class directly (no HTTP layer), following the pattern
# in spec/api/account/get_permissions_spec.rb. Runs in the default (simple)
# auth mode: verify_password delegates to cust.passphrase?, and the
# memoization contract under test is mode-independent.
#
RSpec.describe 'AccountAPI::Logic::Account::RequestEmailChange', type: :integration do
  before(:all) do
    Onetime.boot! :test

    require 'account/logic/account/request_email_change'
  end

  # Distinct error class so assertions can't accidentally match an unrelated
  # StandardError raised elsewhere in the flow.
  simulated_redis_failure = Class.new(StandardError)

  let(:password) { 'testpass123' }
  let(:run_id) { "emailchange_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:new_email) { "#{run_id}-new@test.com" }

  let!(:customer) do
    cust = Onetime::Customer.new(email: "#{run_id}@test.com")
    cust.update_passphrase(password)
    cust.save
    cust
  end

  let(:strategy_result) do
    Otto::Security::Authentication::StrategyResult.new(
      session: { 'authenticated' => true, 'external_id' => customer.extid },
      user: customer,
      auth_method: 'sessionauth',
      strategy_name: 'sessionauth',
      metadata: { ip: '127.0.0.1' },
    )
  end

  let(:rate_limit_key) { "email_change_request:#{customer.objid}" }

  def build_logic(params = {})
    defaults = { 'password' => password, 'new_email' => new_email }
    AccountAPI::Logic::Account::RequestEmailChange.new(strategy_result, defaults.merge(params), 'en')
  end

  def request_count
    Familia.dbclient.get(rate_limit_key).to_i
  end

  before do
    # Keep the focus on quota/verification behavior: no real SMTP/queue work.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)
  end

  describe 'rate-limit quota vs. secret durability (PR #3915 item 3)' do
    it 'consumes quota on a successful request' do
      logic = build_logic
      logic.raise_concerns
      result = logic.process

      expect(result[:sent]).to be(true)
      expect(request_count).to eq(1)
    end

    it 'does NOT consume quota when the secret save fails' do
      allow_any_instance_of(Onetime::Secret)
        .to receive(:save)
        .and_raise(simulated_redis_failure, 'simulated Redis write failure')

      logic = build_logic
      logic.raise_concerns

      expect { logic.process }.to raise_error(simulated_redis_failure)
      expect(request_count).to eq(0)
    end

    it 'still consumes quota when a post-save step (email enqueue) fails' do
      allow(Onetime::Jobs::Publisher)
        .to receive(:enqueue_email)
        .and_raise(StandardError, 'simulated enqueue failure')

      logic = build_logic
      # Silence the expected rescue logging (it dumps the simulated exception's
      # backtrace at :error level, which is pure noise in test output).
      allow(logic).to receive(:auth_logger).and_return(double('auth_logger', error: nil))
      logic.raise_concerns
      result = logic.process

      # Both enqueues are best-effort (each wrapped in begin/rescue); the
      # durable pending-change secret exists, so the request must count.
      expect(result[:sent]).to be(true)
      expect(request_count).to eq(1)
      expect(customer.pending_email_change.to_s).not_to be_empty
    end
  end

  describe 'password verification memoization (PR #3915 item 5)' do
    it 'verifies the password exactly once across raise_concerns + process' do
      logic = build_logic

      expect(logic).to receive(:verify_password).once.and_call_original

      logic.raise_concerns
      result = logic.process

      expect(result[:sent]).to be(true)
    end

    it 'verifies a wrong password exactly once (failed result is memoized)' do
      logic = build_logic('password' => 'wrong-password')

      expect(logic).to receive(:verify_password).once.and_call_original

      expect { logic.raise_concerns }
        .to raise_error(Onetime::FormError, 'Current password is incorrect')
    end
  end
end
