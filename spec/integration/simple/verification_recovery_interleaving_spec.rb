# frozen_string_literal: true

require 'spec_helper'
require 'account/logic'
require File.join(Onetime::HOME, 'apps/api/v2/application')

# Run: tests/lanes/run simple --only spec/integration/simple/verification_recovery_interleaving_spec.rb
# These are scheduled interleavings, not parallel threads: each wrapper returns
# the real check's result after another real request has changed the pointer.
RSpec.describe 'Verification/recovery pointer interleavings', type: :integration do
  let(:new_password) { 'replacement-password123' }

  before(:all) { Onetime.boot! :test }

  before do
    @records = []
    @welcomes = []
    expect(Onetime.auth_config.simple_enabled?).to be true
    expect(OT.conf.dig('site', 'authentication', 'autoverify').to_s).not_to eq('true')

    allow(Onetime::Mail::Mailer).to receive(:deliver) do |_template, data, **|
      secret = data.fetch(:secret)
      @welcomes << secret
      @records.concat([secret, secret.load_receipt])
      true
    end
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |_template, data, **|
      @records << data[:secret] if data[:secret]
      true
    end

    @customer = Onetime::Customer.create!(
      email: "recovery-interleaving-#{SecureRandom.hex(8)}@example.com",
      verified: true,
      verified_by: 'legacy',
    )
    @customer.update_passphrase!('original-password123')
    expect(@customer.mailbox_verified?).to be false
  end

  after do
    # Aggregation ensures one cleanup failure does not skip the other records.
    aggregate_failures('fixture cleanup') do
      @records.compact.reverse_each do |record|
        expect { record.destroy! if record.exists? }.not_to raise_error
      end
      if @customer
        expect { @customer.reset_secret.delete! }.not_to raise_error
        expect do
          Onetime::Customer.dbclient.del("verification_resend:cooldown:#{@customer.objid}")
        end.not_to raise_error
        expect { @customer.destroy! }.not_to raise_error
      end
    end
  end

  def strategy(user: nil)
    Otto::Security::Authentication::StrategyResult.new(
      session: {}, user: user, auth_method: 'noauth', strategy_name: 'noauth', metadata: {},
    )
  end

  def signup
    logic = AccountAPI::Logic::Account::CreateAccount.new(
      strategy, { 'login' => @customer.email, 'password' => 'unrelated-password123', 'skill' => '' },
    )
    logic.raise_concerns
    logic.process
  end

  def request_reset
    logic = AccountAPI::Logic::Authentication::ResetPasswordRequest.new(
      strategy, { 'login' => @customer.email },
    )
    logic.raise_concerns
    logic.process
    secret = Onetime::Secret.find_by_identifier(@customer.reset_secret.value)
    expect(secret).not_to be_nil
    expect(secret.kind).to eq('password_reset')
    secret
  end

  def expect_recovery_to_redeem(secret)
    aggregate_failures('recovery preservation and redemption') do
      expect(@customer.reset_secret.value).to eq(secret.identifier)
      logic = AccountAPI::Logic::Authentication::ResetPassword.new(
        strategy,
        { 'key' => secret.identifier, 'password' => new_password, 'password-confirm' => new_password },
      )
      logic.raise_concerns
      expect { logic.process }.not_to raise_error
      expect(Onetime::Customer.load(@customer.objid).passphrase?(new_password)).to be true
    end
  end

  it 'F6 preserves recovery created after the resend check but before its pointer assignment' do
    expect(@customer.reset_secret.value).to be_nil
    scheduled = 0
    recovery = nil

    # Fault point: Base#send_verification_email has read false from
    # reset_secret_outstanding?, but has not assigned its welcome identifier.
    allow_any_instance_of(Onetime::Customer).to receive(:reset_secret_outstanding?).and_wrap_original do |method, *args|
      result = method.call(*args)
      next result unless method.receiver.objid == @customer.objid

      scheduled += 1
      expect(scheduled).to eq(1)
      expect(result).to be false
      recovery = request_reset
      result
    end

    signup

    expect(scheduled).to eq(1), 'the reset request must run inside the check/write window'
    expect(@welcomes.size).to eq(1)
    expect_recovery_to_redeem(recovery)
  end

  %w[typed legacy].each do |welcome_type|
    it "F7 preserves recovery created after comparing a #{welcome_type} welcome pointer but before deletion" do
      signup
      expect(@welcomes.size).to eq(1)
      welcome = @welcomes.fetch(0)
      expect(welcome.kind).to eq('account_verification')
      expect(welcome.receipt_identifier.to_s).not_to be_empty
      if welcome_type == 'legacy'
        welcome.kind = nil
        welcome.save_fields(:kind)
      end
      expect(@customer.reset_secret.value).to eq(welcome.identifier)
      scheduled = 0
      recovery = nil

      # Fault point: RevealSecret has compared reset_secret to this welcome
      # and read true, but has not issued reset_secret.delete! yet. Returning
      # that actual result lets the caller encounter the now-stale comparison.
      allow_any_instance_of(Onetime::Customer).to receive(:matches_reset_secret?).and_wrap_original do |method, candidate|
        result = method.call(candidate)
        next result unless method.receiver.objid == @customer.objid && candidate.identifier == welcome.identifier

        scheduled += 1
        expect(scheduled).to eq(1)
        expect(result).to be true
        recovery = request_reset
        result
      end

      anonymous = Onetime::Customer.new(role: 'anonymous')
      logic = V2::Logic::Secrets::RevealSecret.new(
        strategy(user: anonymous), { 'identifier' => welcome.identifier, 'continue' => 'true' },
      )
      logic.raise_concerns
      logic.process

      expect(scheduled).to eq(1), 'the reset request must run inside the comparison/delete window'
      expect(logic.show_secret).to be true
      expect_recovery_to_redeem(recovery)
    end
  end
end
