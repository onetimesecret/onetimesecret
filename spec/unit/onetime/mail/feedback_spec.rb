# spec/unit/onetime/mail/feedback_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/feedback/ses'
require 'onetime/mail/feedback/lettermint'

# Unit tests for the deliverability feedback fetchers — the PULL side that reads
# a provider's suppression list and normalizes it into IngestFeedback records.
# Provider SDK clients are stubbed; these assert the walk, the reason mapping,
# the bounds, and the address-only filtering — not real network calls.
RSpec.describe 'Onetime::Mail::Feedback fetchers' do
  describe Onetime::Mail::Feedback::SES do
    let(:client) { instance_double('Aws::SESV2::Client') }

    subject(:fetcher) { described_class.new({}) }

    before { allow(fetcher).to receive(:client).and_return(client) }

    def summary(email, reason)
      double('summary', email_address: email, reason: reason)
    end

    def page(summaries, next_token: nil)
      double('response', suppressed_destination_summaries: summaries, next_token: next_token)
    end

    it 'maps BOUNCE/COMPLAINT to our reasons and imports as suppressions' do
      allow(client).to receive(:list_suppressed_destinations).and_return(
        page([summary('a@example.com', 'BOUNCE'), summary('b@example.com', 'COMPLAINT')]),
      )

      records = fetcher.fetch

      expect(records).to contain_exactly(
        { 'email' => 'a@example.com', 'kind' => 'suppression', 'reason' => 'bounce', 'source' => 'ses' },
        { 'email' => 'b@example.com', 'kind' => 'suppression', 'reason' => 'complaint', 'source' => 'ses' },
      )
    end

    it 'requests only BOUNCE and COMPLAINT reasons' do
      allow(client).to receive(:list_suppressed_destinations).and_return(page([]))

      fetcher.fetch

      expect(client).to have_received(:list_suppressed_destinations)
        .with(hash_including(reasons: %w[BOUNCE COMPLAINT]))
    end

    it 'follows next_token pagination until exhausted' do
      allow(client).to receive(:list_suppressed_destinations).and_return(
        page([summary('p1@example.com', 'BOUNCE')], next_token: 'tok'),
        page([summary('p2@example.com', 'BOUNCE')], next_token: nil),
      )

      emails = fetcher.fetch.map { |r| r['email'] }

      expect(emails).to eq(%w[p1@example.com p2@example.com])
    end

    it 'stops at the requested limit mid-page' do
      big = Array.new(10) { |i| summary("u#{i}@example.com", 'BOUNCE') }
      allow(client).to receive(:list_suppressed_destinations).and_return(page(big))

      expect(fetcher.fetch(limit: 3).size).to eq(3)
    end

    it 'defaults an unexpected reason to manual rather than dropping it' do
      allow(client).to receive(:list_suppressed_destinations).and_return(
        page([summary('c@example.com', 'SOMETHING_NEW')]),
      )

      expect(fetcher.fetch.first['reason']).to eq('manual')
    end
  end

  describe Onetime::Mail::Feedback::Lettermint do
    let(:suppressions) { double('suppressions') }
    let(:team_api) { double('team_api', suppressions: suppressions) }

    subject(:fetcher) { described_class.new('team_token' => 'lm_team_x') }

    before { allow(fetcher).to receive(:team_api).and_return(team_api) }

    def envelope(rows, next_cursor: nil)
      { 'data' => rows, 'pagination' => { 'next_cursor' => next_cursor } }
    end

    it 'maps Lettermint reasons and imports address suppressions' do
      allow(suppressions).to receive(:list).and_return(
        envelope(
          [
            { 'value' => 'a@example.com', 'reason' => 'hard_bounce' },
            { 'value' => 'b@example.com', 'reason' => 'spam_complaint' },
            { 'value' => 'c@example.com', 'reason' => 'unsubscribe' },
          ],
        ),
      )

      records = fetcher.fetch

      expect(records).to contain_exactly(
        { 'email' => 'a@example.com', 'kind' => 'suppression', 'reason' => 'bounce', 'source' => 'lettermint' },
        { 'email' => 'b@example.com', 'kind' => 'suppression', 'reason' => 'complaint', 'source' => 'lettermint' },
        { 'email' => 'c@example.com', 'kind' => 'suppression', 'reason' => 'manual', 'source' => 'lettermint' },
      )
    end

    it 'skips domain/extension suppressions (address-level list only)' do
      allow(suppressions).to receive(:list).and_return(
        envelope(
          [
            { 'value' => 'user@example.com', 'reason' => 'hard_bounce' },
            { 'value' => 'example.com', 'reason' => 'hard_bounce' },   # domain scope
            { 'value' => '@example.org', 'reason' => 'manual' },       # extension-ish, has @
          ],
        ),
      )

      emails = fetcher.fetch.map { |r| r['email'] }

      expect(emails).to include('user@example.com')
      expect(emails).not_to include('example.com')
    end

    it 'follows the page cursor until it is empty' do
      allow(suppressions).to receive(:list).and_return(
        envelope([{ 'value' => 'p1@example.com', 'reason' => 'manual' }], next_cursor: 'c2'),
        envelope([{ 'value' => 'p2@example.com', 'reason' => 'manual' }], next_cursor: nil),
      )

      emails = fetcher.fetch.map { |r| r['email'] }

      expect(emails).to eq(%w[p1@example.com p2@example.com])
      expect(suppressions).to have_received(:list).twice
    end

    it 'raises a clear error when the team token is missing' do
      # Exercise the real team_api builder (not the stub) for this check.
      bare = described_class.new({})
      allow(bare).to receive(:team_api).and_call_original

      expect { bare.fetch }.to raise_error(ArgumentError, /team token/i)
    end
  end
end
