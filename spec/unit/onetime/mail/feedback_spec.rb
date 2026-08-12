# spec/unit/onetime/mail/feedback_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'time'
require 'onetime/mail/feedback/ses'
require 'onetime/mail/feedback/lettermint'
require 'onetime/mail/feedback/smtp2go'

# Unit tests for the deliverability feedback fetchers — the PULL side that reads
# a provider's suppression list and normalizes it into IngestFeedback records.
# Provider SDK clients are stubbed; these assert the walk, the reason mapping,
# the bounds, and the address-only filtering — not real network calls. The
# SMTP2GO block also covers the live per-address #lookup (exact-match only,
# raw provider reason) and the #stats cycle summary (nil-preserving percents).
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

  describe Onetime::Mail::Feedback::Smtp2go do
    let(:client) { instance_double(Onetime::Mail::Smtp2goClient) }

    subject(:fetcher) { described_class.new('api_key' => 'api-xxx') }

    before { allow(fetcher).to receive(:client).and_return(client) }

    # Smtp2goClient#post unwraps the {request_id, data:{...}} envelope, so the
    # stub returns the `data` hash directly (rows under 'suppressions').
    def data(rows)
      { 'suppressions' => rows }
    end

    it 'maps SMTP2GO reasons (bounce/spam/unsubscribe/manual) and imports address suppressions' do
      allow(client).to receive(:post).with('/suppression/view', {}).and_return(
        data(
          [
            { 'email_address' => 'a@example.com', 'reason' => 'bounce' },
            { 'email_address' => 'b@example.com', 'reason' => 'spam' },
            { 'email_address' => 'c@example.com', 'reason' => 'unsubscribe' },
            { 'email_address' => 'd@example.com', 'reason' => 'manual' },
          ],
        ),
      )

      records = fetcher.fetch

      expect(records).to contain_exactly(
        { 'email' => 'a@example.com', 'kind' => 'suppression', 'reason' => 'bounce', 'source' => 'smtp2go' },
        { 'email' => 'b@example.com', 'kind' => 'suppression', 'reason' => 'complaint', 'source' => 'smtp2go' },
        { 'email' => 'c@example.com', 'kind' => 'suppression', 'reason' => 'manual', 'source' => 'smtp2go' },
        { 'email' => 'd@example.com', 'kind' => 'suppression', 'reason' => 'manual', 'source' => 'smtp2go' },
      )
    end

    it 'skips domain-scoped suppressions (address-level list only)' do
      allow(client).to receive(:post).and_return(
        data(
          [
            { 'email_address' => 'user@example.com', 'reason' => 'bounce' },
            { 'email_address' => '@example.com', 'reason' => 'spam' },  # domain scope
            { 'email_address' => 'example.org', 'reason' => 'manual' }, # no @ at all
          ],
        ),
      )

      emails = fetcher.fetch.map { |r| r['email'] }

      expect(emails).to eq(%w[user@example.com])
    end

    it 'stops at the requested limit' do
      rows = Array.new(10) { |i| { 'email_address' => "u#{i}@example.com", 'reason' => 'bounce' } }
      allow(client).to receive(:post).and_return(data(rows))

      expect(fetcher.fetch(limit: 3).size).to eq(3)
    end

    it 'defaults an unexpected reason to manual rather than dropping it' do
      allow(client).to receive(:post).and_return(
        data([{ 'email_address' => 'c@example.com', 'reason' => 'something_new' }]),
      )

      expect(fetcher.fetch.first['reason']).to eq('manual')
    end

    it 'returns no records when the response carries no suppressions' do
      allow(client).to receive(:post).and_return({})

      expect(fetcher.fetch).to eq([])
    end

    it 'raises a clear error when the API key is missing' do
      # Exercise the real client builder (not the stub) for this check.
      bare = described_class.new({})
      allow(bare).to receive(:client).and_call_original

      expect { bare.fetch }.to raise_error(ArgumentError, /api key/i)
    end

    it 'lookup keeps only the exact-match row, returning the RAW reason + parsed timestamp' do
      # The email_address filter accepts wildcards, so the response can carry
      # loose matches; only the exact row may count (contract §4 rule 9).
      allow(client).to receive(:post).with(
        '/suppression/view', { 'email_address' => 'user@example.com' },
      ).and_return(
        data(
          [
            { 'email_address' => 'other-user@example.com', 'reason' => 'bounce',
              'timestamp' => '2021-01-01T00:00:00' },
            { 'email_address' => 'user@example.com', 'reason' => 'spam',
              'timestamp' => '2021-04-30T00:00:00' },
          ],
        ),
      )

      result = fetcher.lookup('user@example.com')

      expect(result).to eq(
        suppressed: true,
        # RAW SMTP2GO reason ('spam'), NOT the REASON_MAP'd 'complaint'.
        reason: 'spam',
        last_update_time: Time.parse('2021-04-30T00:00:00').to_i,
      )
    end

    it 'lookup reports not-suppressed when the response carries only loose matches' do
      allow(client).to receive(:post).and_return(
        data([{ 'email_address' => 'prefix-user@example.com', 'reason' => 'bounce' }]),
      )

      expect(fetcher.lookup('user@example.com')).to eq(
        suppressed: false, reason: nil, last_update_time: nil,
      )
    end

    it 'lookup reports not-suppressed for an empty suppression list' do
      allow(client).to receive(:post).and_return(data([]))

      expect(fetcher.lookup('user@example.com')).to eq(
        suppressed: false, reason: nil, last_update_time: nil,
      )
    end

    it 'stats maps the /stats/email_summary fields (counts to Integer, percents to Float)' do
      allow(client).to receive(:post).with('/stats/email_summary', {}).and_return(
        {
          'cycle_start' => '2021-04-01T00:00:00', 'cycle_end' => '2021-05-01T00:00:00',
          'cycle_used' => 550, 'cycle_remaining' => 450, 'cycle_max' => 1000,
          'email_count' => 550, 'bounce_rejects' => 10, 'softbounces' => 10,
          'hardbounces' => 10, 'bounce_percent' => 5.5, 'spam_rejects' => 10,
          'spam_percent' => 1.8, 'unsubscribes' => 10,
        },
      )

      expect(fetcher.stats).to eq(
        cycle_start: '2021-04-01T00:00:00',
        cycle_end: '2021-05-01T00:00:00',
        cycle_used: 550,
        cycle_remaining: 450,
        cycle_max: 1000,
        email_count: 550,
        bounce_rejects: 10,
        softbounces: 10,
        hardbounces: 10,
        spam_rejects: 10,
        unsubscribes: 10,
        bounce_percent: 5.5,
        spam_percent: 1.8,
      )
    end

    it 'stats preserves nil for percentages the provider omits (never a fake 0.0)' do
      allow(client).to receive(:post).with('/stats/email_summary', {}).and_return(
        { 'cycle_used' => 0, 'cycle_remaining' => 1000, 'cycle_max' => 1000 },
      )

      summary = fetcher.stats

      expect(summary[:bounce_percent]).to be_nil
      expect(summary[:spam_percent]).to be_nil
      expect(summary[:email_count]).to eq(0)
    end
  end
end
