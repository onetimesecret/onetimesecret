# spec/unit/onetime/cli/migrations/backfill_stripe_email_hash_command_spec.rb
#
# frozen_string_literal: true

# Unit tests for BackfillStripeEmailHashCommand#process_stripe_customer.
#
# Covers retry logic for Stripe::RateLimitError (up to MAX_RATE_LIMIT_RETRIES),
# fallthrough to error recording for non-retryable Stripe errors, and general
# StandardError handling.
#
# Run: pnpm run test:rspec spec/unit/onetime/cli/migrations/backfill_stripe_email_hash_command_spec.rb

require 'spec_helper'
require 'onetime/cli'

RSpec.describe Onetime::CLI::BackfillStripeEmailHashCommand do
  subject(:command) { described_class.new }

  let(:stripe_customer_id) { 'cus_abc123' }
  let(:billing_email) { 'user@example.com' }
  let(:email_hash) { 'abcdef01' * 4 }

  let(:org) do
    double('Organization',
      extid: 'org_ext_1',
      stripe_customer_id: stripe_customer_id,
      billing_email: billing_email,
    )
  end

  # A customer with no pre-existing email_hash metadata.
  let(:stripe_customer) do
    double('Stripe::Customer',
      metadata: {},
    )
  end

  let(:stats) do
    { total: 0, updated: 0, skipped_no_email: 0, skipped_has_hash: 0, errors: [] }
  end

  before do
    allow(command).to receive(:puts)
    allow(command).to receive(:print)
    allow(command).to receive(:print_progress)
    allow(command).to receive(:sleep)
    allow(OT).to receive(:le)
    allow(Onetime::Utils::EmailHash).to receive(:compute).with(billing_email).and_return(email_hash)
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe '#process_stripe_customer (happy path)' do
    before do
      allow(Stripe::Customer).to receive(:retrieve).with(stripe_customer_id).and_return(stripe_customer)
      allow(Stripe::Customer).to receive(:update)
    end

    it 'increments stats[:total] and stats[:updated]' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(stats[:total]).to eq(1)
      expect(stats[:updated]).to eq(1)
    end

    it 'calls Stripe::Customer.update with email_hash and migration marker in metadata' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(Stripe::Customer).to have_received(:update).with(
        stripe_customer_id,
        metadata: hash_including('email_hash' => email_hash, 'email_hash_migrated' => 'true'),
      )
    end

    it 'does not call Stripe::Customer.update in dry-run mode' do
      command.send(:process_stripe_customer, org, 0, 1, stats, true, false)

      expect(Stripe::Customer).not_to have_received(:update)
    end

    it 'still increments stats[:updated] in dry-run mode (counts the preview)' do
      command.send(:process_stripe_customer, org, 0, 1, stats, true, false)

      expect(stats[:updated]).to eq(1)
    end

    it 'skips customer that already has email_hash in Stripe metadata' do
      customer_with_hash = double('Stripe::Customer', metadata: { 'email_hash' => 'existing_hash' })
      allow(Stripe::Customer).to receive(:retrieve).and_return(customer_with_hash)

      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(stats[:skipped_has_hash]).to eq(1)
      expect(stats[:updated]).to eq(0)
      expect(Stripe::Customer).not_to have_received(:update)
    end
  end

  # ---------------------------------------------------------------------------
  # Retry logic for Stripe::RateLimitError
  # ---------------------------------------------------------------------------

  describe '#process_stripe_customer retry on Stripe::RateLimitError' do
    let(:rate_limit_error) { Stripe::RateLimitError.new('Rate limit exceeded') }

    context 'when rate-limited once then succeeds' do
      before do
        call_count = 0
        allow(Stripe::Customer).to receive(:retrieve) do
          call_count += 1
          raise rate_limit_error if call_count == 1
          stripe_customer
        end
        allow(Stripe::Customer).to receive(:update)
      end

      it 'retries and completes successfully' do
        command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

        expect(Stripe::Customer).to have_received(:retrieve).twice
        expect(stats[:updated]).to eq(1)
        expect(stats[:errors]).to be_empty
      end

      it 'sleeps before the retry' do
        command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

        expect(command).to have_received(:sleep).with(5).once
      end
    end

    context 'when rate-limited exactly MAX_RATE_LIMIT_RETRIES times then succeeds' do
      let(:max) { described_class::MAX_RATE_LIMIT_RETRIES }

      before do
        call_count = 0
        allow(Stripe::Customer).to receive(:retrieve) do
          call_count += 1
          raise rate_limit_error if call_count <= max
          stripe_customer
        end
        allow(Stripe::Customer).to receive(:update)
      end

      it 'retries up to the limit and succeeds on the final attempt' do
        command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

        expect(Stripe::Customer).to have_received(:retrieve).exactly(max + 1).times
        expect(stats[:updated]).to eq(1)
        expect(stats[:errors]).to be_empty
      end
    end

    context 'when rate-limited more than MAX_RATE_LIMIT_RETRIES times' do
      let(:max) { described_class::MAX_RATE_LIMIT_RETRIES }

      before do
        allow(Stripe::Customer).to receive(:retrieve).and_raise(rate_limit_error)
      end

      it 'records a stripe error after exhausting retries' do
        command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

        expect(Stripe::Customer).to have_received(:retrieve).exactly(max + 1).times
        expect(stats[:errors].size).to eq(1)
        expect(stats[:updated]).to eq(0)
      end

      it 'sleeps with linearly increasing backoff between each retry attempt' do
        command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

        # Expected sleeps: 5*1=5, 5*2=10, 5*3=15 (for MAX_RATE_LIMIT_RETRIES=3)
        (1..max).each_with_index do |n, idx|
          expect(command).to have_received(:sleep).with(5 * n)
        end
        expect(command).to have_received(:sleep).exactly(max).times
      end

      it 'includes the customer id in the recorded error message' do
        command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

        expect(stats[:errors].first).to include(stripe_customer_id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Non-retryable Stripe errors
  # ---------------------------------------------------------------------------

  describe '#process_stripe_customer on non-retryable Stripe::StripeError' do
    let(:stripe_error) { Stripe::InvalidRequestError.new('No such customer', 'id') }

    before do
      allow(Stripe::Customer).to receive(:retrieve).and_raise(stripe_error)
    end

    it 'records the error without retrying' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(Stripe::Customer).to have_received(:retrieve).once
      expect(stats[:errors].size).to eq(1)
    end

    it 'includes the stripe customer id in the recorded error' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(stats[:errors].first).to include(stripe_customer_id)
    end

    it 'does not sleep' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(command).not_to have_received(:sleep)
    end
  end

  # ---------------------------------------------------------------------------
  # General (non-Stripe) errors
  # ---------------------------------------------------------------------------

  describe '#process_stripe_customer on StandardError' do
    let(:general_error) { RuntimeError.new('unexpected application error') }

    before do
      allow(Stripe::Customer).to receive(:retrieve).and_raise(general_error)
    end

    it 'records the error using org extid' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include(org.extid)
    end

    it 'does not retry' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(Stripe::Customer).to have_received(:retrieve).once
    end

    it 'does not sleep' do
      command.send(:process_stripe_customer, org, 0, 1, stats, false, false)

      expect(command).not_to have_received(:sleep)
    end
  end
end
