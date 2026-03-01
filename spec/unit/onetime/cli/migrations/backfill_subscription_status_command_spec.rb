# spec/unit/onetime/cli/migrations/backfill_subscription_status_command_spec.rb
#
# frozen_string_literal: true

# Unit tests for BackfillSubscriptionStatusCommand#process_org.
#
# Covers:
# - Dry-run mode (no mutations, correct preview output)
# - Run mode (org fields updated, org.save_fields called)
# - Idempotent skip (org already has subscription_status)
# - Deleted subscription handling (Stripe::InvalidRequestError with resource_missing)
# - Non-resource_missing InvalidRequestError (falls through to error recording)
# - Retry logic for Stripe::RateLimitError (up to MAX_RATE_LIMIT_RETRIES)
# - General Stripe::StripeError handling
# - General StandardError handling
#
# Run: pnpm run test:rspec spec/unit/onetime/cli/migrations/backfill_subscription_status_command_spec.rb

require 'spec_helper'
require 'onetime/cli'

RSpec.describe Onetime::CLI::BackfillSubscriptionStatusCommand do
  subject(:command) { described_class.new }

  let(:stripe_subscription_id) { 'sub_abc123' }
  let(:subscription_status) { 'active' }
  let(:period_end) { 1_700_000_000 }

  let(:org) do
    double('Organization',
      extid: 'org_ext_1',
      stripe_subscription_id: stripe_subscription_id,
      subscription_status: nil,
      :subscription_status= => nil,
      :subscription_period_end= => nil,
      save_fields: true,
    )
  end

  # Stripe subscription with nested items structure
  let(:stripe_subscription) do
    item = double('SubscriptionItem', current_period_end: period_end)
    items_data = double('ItemsData', data: [item])
    double('Stripe::Subscription',
      status: subscription_status,
      items: items_data,
    )
  end

  let(:stats) do
    { total: 0, updated: 0, skipped_has_status: 0, skipped_deleted: 0, errors: [] }
  end

  before do
    allow(command).to receive(:puts)
    allow(command).to receive(:print)
    allow(command).to receive(:print_progress)
    allow(command).to receive(:sleep)
    allow(OT).to receive(:le)
    allow(OT).to receive(:lw)
  end

  # ---------------------------------------------------------------------------
  # Happy path -- run mode
  # ---------------------------------------------------------------------------

  describe '#process_org (run mode)' do
    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id).and_return(stripe_subscription)
    end

    it 'increments stats[:total] and stats[:updated]' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:total]).to eq(1)
      expect(stats[:updated]).to eq(1)
    end

    it 'sets subscription_status on the org' do
      expect(org).to receive(:subscription_status=).with('active')

      command.send(:process_org, org, 0, 1, stats, false, false)
    end

    it 'sets subscription_period_end on the org' do
      expect(org).to receive(:subscription_period_end=).with(period_end.to_s)

      command.send(:process_org, org, 0, 1, stats, false, false)
    end

    it 'calls org.save_fields with updated fields' do
      expect(org).to receive(:save_fields).with(:subscription_status, :subscription_period_end)

      command.send(:process_org, org, 0, 1, stats, false, false)
    end

    it 'sleeps for rate limiting after update' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(command).to have_received(:sleep).with(described_class::BATCH_DELAY_SECONDS)
    end
  end

  # ---------------------------------------------------------------------------
  # Dry-run mode
  # ---------------------------------------------------------------------------

  describe '#process_org (dry-run mode)' do
    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id).and_return(stripe_subscription)
    end

    it 'does not set subscription_status on the org' do
      expect(org).not_to receive(:subscription_status=)

      command.send(:process_org, org, 0, 1, stats, true, false)
    end

    it 'does not call org.save_fields' do
      expect(org).not_to receive(:save_fields)

      command.send(:process_org, org, 0, 1, stats, true, false)
    end

    it 'still increments stats[:updated] (counts the preview)' do
      command.send(:process_org, org, 0, 1, stats, true, false)

      expect(stats[:updated]).to eq(1)
    end

    it 'does not sleep for rate limiting' do
      command.send(:process_org, org, 0, 1, stats, true, false)

      expect(command).not_to have_received(:sleep)
    end

    it 'outputs a would-update message when verbose' do
      command.send(:process_org, org, 0, 1, stats, true, true)

      expect(command).to have_received(:puts).with(
        a_string_matching(/Would update.*org_ext_1.*status=active.*period_end=#{period_end}/)
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotent skip -- org already has subscription_status
  # ---------------------------------------------------------------------------

  describe '#process_org skipping orgs with existing subscription_status' do
    let(:org_with_status) do
      double('Organization',
        extid: 'org_ext_2',
        stripe_subscription_id: stripe_subscription_id,
        subscription_status: 'active',
      )
    end

    it 'increments stats[:skipped_has_status]' do
      command.send(:process_org, org_with_status, 0, 1, stats, false, false)

      expect(stats[:skipped_has_status]).to eq(1)
    end

    it 'does not call Stripe::Subscription.retrieve' do
      expect(Stripe::Subscription).not_to receive(:retrieve)

      command.send(:process_org, org_with_status, 0, 1, stats, false, false)
    end

    it 'does not increment stats[:updated]' do
      command.send(:process_org, org_with_status, 0, 1, stats, false, false)

      expect(stats[:updated]).to eq(0)
    end

    it 'outputs a skip message when verbose' do
      command.send(:process_org, org_with_status, 0, 1, stats, false, true)

      expect(command).to have_received(:puts).with(
        a_string_matching(/Skipping.*has status 'active'.*org_ext_2/)
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Deleted subscription handling (resource_missing)
  # ---------------------------------------------------------------------------

  describe '#process_org on Stripe::InvalidRequestError with resource_missing' do
    let(:resource_missing_error) do
      Stripe::InvalidRequestError.new(
        'No such subscription: sub_abc123', 'id', code: 'resource_missing'
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(resource_missing_error)
    end

    it 'increments stats[:skipped_deleted]' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:skipped_deleted]).to eq(1)
    end

    it 'does not record an error' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:errors]).to be_empty
    end

    it 'does not call org.save_fields' do
      expect(org).not_to receive(:save_fields)

      command.send(:process_org, org, 0, 1, stats, false, false)
    end

    it 'logs a warning via OT.lw' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(OT).to have_received(:lw).with(
        a_string_matching(/Subscription not found.*sub_abc123.*org_ext_1/)
      )
    end

    it 'outputs skip message when verbose' do
      command.send(:process_org, org, 0, 1, stats, false, true)

      expect(command).to have_received(:puts).with(
        a_string_matching(/Skipping.*subscription not found.*sub_abc123/)
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Non-resource_missing InvalidRequestError
  # ---------------------------------------------------------------------------

  describe '#process_org on Stripe::InvalidRequestError without resource_missing' do
    let(:invalid_request_error) do
      Stripe::InvalidRequestError.new('Invalid subscription', 'id', code: 'invalid_request')
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(invalid_request_error)
    end

    it 'records a stripe error' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:errors].size).to eq(1)
    end

    it 'does not increment stats[:skipped_deleted]' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:skipped_deleted]).to eq(0)
    end

    it 'includes the subscription id in the error message' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:errors].first).to include(stripe_subscription_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Retry logic for Stripe::RateLimitError
  # ---------------------------------------------------------------------------

  describe '#process_org retry on Stripe::RateLimitError' do
    let(:rate_limit_error) { Stripe::RateLimitError.new('Rate limit exceeded') }

    context 'when rate-limited once then succeeds' do
      before do
        call_count = 0
        allow(Stripe::Subscription).to receive(:retrieve) do
          call_count += 1
          raise rate_limit_error if call_count == 1
          stripe_subscription
        end
      end

      it 'retries and completes successfully' do
        command.send(:process_org, org, 0, 1, stats, false, false)

        expect(Stripe::Subscription).to have_received(:retrieve).twice
        expect(stats[:updated]).to eq(1)
        expect(stats[:errors]).to be_empty
      end

      it 'sleeps with 5s backoff before the retry' do
        command.send(:process_org, org, 0, 1, stats, false, false)

        expect(command).to have_received(:sleep).with(5).once
      end
    end

    context 'when rate-limited exactly MAX_RATE_LIMIT_RETRIES times then succeeds' do
      let(:max) { described_class::MAX_RATE_LIMIT_RETRIES }

      before do
        call_count = 0
        allow(Stripe::Subscription).to receive(:retrieve) do
          call_count += 1
          raise rate_limit_error if call_count <= max
          stripe_subscription
        end
      end

      it 'retries up to the limit and succeeds on the final attempt' do
        command.send(:process_org, org, 0, 1, stats, false, false)

        expect(Stripe::Subscription).to have_received(:retrieve).exactly(max + 1).times
        expect(stats[:updated]).to eq(1)
        expect(stats[:errors]).to be_empty
      end
    end

    context 'when rate-limited more than MAX_RATE_LIMIT_RETRIES times' do
      let(:max) { described_class::MAX_RATE_LIMIT_RETRIES }

      before do
        allow(Stripe::Subscription).to receive(:retrieve).and_raise(rate_limit_error)
      end

      it 'records a stripe error after exhausting retries' do
        command.send(:process_org, org, 0, 1, stats, false, false)

        expect(Stripe::Subscription).to have_received(:retrieve).exactly(max + 1).times
        expect(stats[:errors].size).to eq(1)
        expect(stats[:updated]).to eq(0)
      end

      it 'sleeps with linearly increasing backoff between each retry attempt' do
        command.send(:process_org, org, 0, 1, stats, false, false)

        (1..max).each do |n|
          expect(command).to have_received(:sleep).with(5 * n)
        end
        expect(command).to have_received(:sleep).exactly(max).times
      end

      it 'includes the subscription id in the recorded error message' do
        command.send(:process_org, org, 0, 1, stats, false, false)

        expect(stats[:errors].first).to include(stripe_subscription_id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Non-retryable Stripe errors
  # ---------------------------------------------------------------------------

  describe '#process_org on non-retryable Stripe::StripeError' do
    let(:stripe_error) { Stripe::APIError.new('Internal server error') }

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(stripe_error)
    end

    it 'records the error without retrying' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(Stripe::Subscription).to have_received(:retrieve).once
      expect(stats[:errors].size).to eq(1)
    end

    it 'includes the subscription id in the recorded error' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:errors].first).to include(stripe_subscription_id)
    end

    it 'does not sleep' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(command).not_to have_received(:sleep)
    end
  end

  # ---------------------------------------------------------------------------
  # General (non-Stripe) errors
  # ---------------------------------------------------------------------------

  describe '#process_org on StandardError' do
    let(:general_error) { RuntimeError.new('unexpected application error') }

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(general_error)
    end

    it 'records the error using org extid' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include(org.extid)
    end

    it 'does not retry' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(Stripe::Subscription).to have_received(:retrieve).once
    end

    it 'does not sleep' do
      command.send(:process_org, org, 0, 1, stats, false, false)

      expect(command).not_to have_received(:sleep)
    end
  end

  # ---------------------------------------------------------------------------
  # find_orgs_with_subscription
  # ---------------------------------------------------------------------------

  describe '#find_orgs_with_subscription' do
    let(:org_with_sub) do
      double('Organization', stripe_subscription_id: 'sub_123')
    end

    let(:org_without_sub) do
      double('Organization', stripe_subscription_id: nil)
    end

    let(:org_empty_sub) do
      double('Organization', stripe_subscription_id: '')
    end

    before do
      instances = double('instances', all: %w[id1 id2 id3])
      allow(Onetime::Organization).to receive(:instances).and_return(instances)
      allow(Onetime::Organization).to receive(:load_multi)
        .with(%w[id1 id2 id3])
        .and_return([org_with_sub, org_without_sub, org_empty_sub])
    end

    it 'returns only orgs with non-empty stripe_subscription_id' do
      result = command.send(:find_orgs_with_subscription)

      expect(result).to eq([org_with_sub])
    end

    it 'returns empty array and prints message when no orgs found' do
      allow(Onetime::Organization).to receive(:instances)
        .and_return(double('instances', all: []))
      allow(Onetime::Organization).to receive(:load_multi)
        .with([]).and_return([])

      result = command.send(:find_orgs_with_subscription)

      expect(result).to be_empty
      expect(command).to have_received(:puts).with(
        a_string_matching(/No organizations with Stripe subscription IDs found/)
      )
    end
  end

  # ---------------------------------------------------------------------------
  # verify_stripe_configured!
  # ---------------------------------------------------------------------------

  describe '#verify_stripe_configured!' do
    it 'returns true when Stripe.api_key is set' do
      allow(Stripe).to receive(:api_key).and_return('sk_test_123')

      expect(command.send(:verify_stripe_configured!)).to be true
    end

    it 'returns false and prints message when Stripe.api_key is empty' do
      allow(Stripe).to receive(:api_key).and_return('')

      expect(command.send(:verify_stripe_configured!)).to be false
      expect(command).to have_received(:puts).with(
        a_string_matching(/Stripe API not configured/)
      )
    end

    it 'returns false when Stripe.api_key is nil' do
      allow(Stripe).to receive(:api_key).and_return(nil)

      expect(command.send(:verify_stripe_configured!)).to be false
    end
  end
end
