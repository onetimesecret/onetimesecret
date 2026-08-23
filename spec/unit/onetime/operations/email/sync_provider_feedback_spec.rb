# spec/unit/onetime/operations/email/sync_provider_feedback_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/email/sync_provider_feedback'

# Unit tests for the sync orchestration: provider selection, the fetch ->
# IngestFeedback hand-off, dry-run, and the unsupported-provider guard. The
# fetcher and IngestFeedback are stubbed — the provider walk and the model
# writes have their own specs; this pins the wiring between them.
RSpec.describe Onetime::Operations::Email::SyncProviderFeedback do
  let(:records) do
    [
      { 'email' => 'a@example.com', 'kind' => 'suppression', 'reason' => 'bounce', 'source' => 'ses' },
      { 'email' => 'b@example.com', 'kind' => 'suppression', 'reason' => 'complaint', 'source' => 'ses' },
    ]
  end
  let(:fetcher) { double('fetcher') }

  before do
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return({})
    allow(Onetime::Mail::Feedback::SES).to receive(:new).and_return(fetcher)
  end

  it 'fetches the provider list and ingests it, returning the tallies' do
    allow(fetcher).to receive(:fetch).and_return(records)
    ingest = instance_double(
      Onetime::Operations::Email::IngestFeedback,
      call: Onetime::Operations::Email::IngestFeedback::Result.new(accepted: 2, rejected: 0, errors: []),
    )
    expect(Onetime::Operations::Email::IngestFeedback).to receive(:new).with(
      records: records, actor: described_class::CLI_ACTOR, default_source: 'ses'
    ).and_return(ingest)

    result = described_class.new(provider: 'ses').call

    expect(result.provider).to eq('ses')
    expect(result.fetched).to eq(2)
    expect(result.accepted).to eq(2)
    expect(result.dry_run).to be(false)
  end

  it 'passes an explicit limit through to the fetcher' do
    expect(fetcher).to receive(:fetch).with(limit: 50).and_return([])

    described_class.new(provider: 'ses', limit: 50).call
  end

  it 'dry-run fetches but never ingests' do
    allow(fetcher).to receive(:fetch).and_return(records)
    expect(Onetime::Operations::Email::IngestFeedback).not_to receive(:new)

    result = described_class.new(provider: 'ses', dry_run: true).call

    expect(result.fetched).to eq(2)
    expect(result.accepted).to eq(0)
    expect(result.dry_run).to be(true)
  end

  it 'skips ingestion when the provider list is empty but still stamps sync_status' do
    Onetime::EmailSuppression.sync_status.clear
    allow(fetcher).to receive(:fetch).and_return([])
    expect(Onetime::Operations::Email::IngestFeedback).not_to receive(:new)

    result = described_class.new(provider: 'ses').call

    expect(result.fetched).to eq(0)
    expect(result.accepted).to eq(0)
    expect(Onetime::EmailSuppression.sync_status['ses']).to include('imported' => 0, 'result' => 'ok')
  end

  it 'a dry run never stamps sync_status' do
    Onetime::EmailSuppression.sync_status.clear
    allow(fetcher).to receive(:fetch).and_return(records)

    described_class.new(provider: 'ses', dry_run: true).call

    expect(Onetime::EmailSuppression.sync_status['ses']).to be_nil
  end

  it 'defaults the provider to the configured delivery provider' do
    allow(Onetime::Mail::Mailer).to receive(:determine_provider).and_return('ses')
    allow(fetcher).to receive(:fetch).and_return([])

    expect(described_class.new.call.provider).to eq('ses')
  end

  it 'raises for a provider with no feedback API' do
    expect { described_class.new(provider: 'smtp').call }
      .to raise_error(ArgumentError, /no feedback API/i)
  end

  context 'with the smtp2go provider' do
    let(:smtp2go_records) do
      [
        { 'email' => 'a@example.com', 'kind' => 'suppression', 'reason' => 'bounce', 'source' => 'smtp2go' },
        { 'email' => 'b@example.com', 'kind' => 'suppression', 'reason' => 'complaint', 'source' => 'smtp2go' },
      ]
    end

    before do
      allow(Onetime::Mail::Feedback::Smtp2go).to receive(:new).and_return(fetcher)
    end

    it 'is a supported feedback provider' do
      expect(described_class::PROVIDERS).to include('smtp2go')
    end

    it 'builds the smtp2go fetcher from smtp2go credentials and ingests its list' do
      allow(fetcher).to receive(:fetch).and_return(smtp2go_records)
      ingest = instance_double(
        Onetime::Operations::Email::IngestFeedback,
        call: Onetime::Operations::Email::IngestFeedback::Result.new(accepted: 2, rejected: 0, errors: []),
      )
      expect(Onetime::Operations::Email::IngestFeedback).to receive(:new).with(
        records: smtp2go_records, actor: described_class::CLI_ACTOR, default_source: 'smtp2go'
      ).and_return(ingest)

      result = described_class.new(provider: 'smtp2go').call

      expect(Onetime::Mail::Mailer).to have_received(:provider_credentials).with('smtp2go')
      expect(result.provider).to eq('smtp2go')
      expect(result.fetched).to eq(2)
      expect(result.accepted).to eq(2)
      expect(result.dry_run).to be(false)
    end

    it 'stamps sync_status under the smtp2go key' do
      Onetime::EmailSuppression.sync_status.clear
      allow(fetcher).to receive(:fetch).and_return([])

      described_class.new(provider: 'smtp2go').call

      expect(Onetime::EmailSuppression.sync_status['smtp2go']).to include('imported' => 0, 'result' => 'ok')
    end
  end
end
