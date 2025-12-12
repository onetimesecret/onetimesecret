# spec/onetime/jobs/scheduled/expiration_warning_job_spec.rb
#
# frozen_string_literal: true

# ExpirationWarningJob Test Suite
#
# Tests the scheduled job that scans for expiring secrets and schedules
# warning emails to their owners.
#
# Test Categories:
#
#   1. Scheduling (Unit)
#      - Verifies job schedules when enabled
#      - Verifies job skips scheduling when disabled
#
#   2. Configuration (Unit)
#      - Tests warning_hours default and custom values
#      - Tests enabled? check
#
#   3. Secret Processing (Integration)
#      - Tests expiring_within query
#      - Tests deduplication via warning_sent?
#      - Tests anonymous secret filtering
#      - Tests owner email validation
#      - Tests warning email scheduling
#      - Tests timeline cleanup
#
# Setup Requirements:
#   - Mocked OT.conf for configuration
#   - Mocked Metadata class methods
#   - Mocked Publisher.schedule_email
#
# Run with: pnpm run test:rspec spec/onetime/jobs/scheduled/expiration_warning_job_spec.rb

require 'spec_helper'
require 'rufus-scheduler'
require_relative '../../../../lib/onetime/jobs/scheduled/expiration_warning_job'
require_relative '../../../../lib/onetime/jobs/publisher'

RSpec.describe Onetime::Jobs::Scheduled::ExpirationWarningJob do
  let(:scheduler) { instance_double(Rufus::Scheduler) }

  # Mock owner with email
  let(:owner_with_email) do
    instance_double('Onetime::Customer', email: 'owner@example.com')
  end

  # Mock owner without email
  let(:owner_without_email) do
    instance_double('Onetime::Customer', email: nil)
  end

  # Mock metadata with owner
  let(:metadata_with_owner) do
    instance_double(
      'Onetime::Metadata',
      identifier: 'meta123',
      exists?: true,
      anonymous?: false,
      load_owner: owner_with_email,
      secret_shortid: 'abc123',
      secret_expiration: (Familia.now.to_i + 7200), # 2 hours from now
      share_domain: nil
    )
  end

  # Mock anonymous metadata
  let(:anonymous_metadata) do
    instance_double(
      'Onetime::Metadata',
      identifier: 'meta456',
      exists?: true,
      anonymous?: true
    )
  end

  # Mock metadata without owner email
  let(:metadata_no_email) do
    instance_double(
      'Onetime::Metadata',
      identifier: 'meta789',
      exists?: true,
      anonymous?: false,
      load_owner: owner_without_email
    )
  end

  describe '.schedule' do
    context 'when enabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'expiration_warnings' => {
              'enabled' => true,
              'check_interval' => '1h'
            }
          }
        })
      end

      it 'registers an interval job with the scheduler' do
        expect(scheduler).to receive(:every).with('1h', first_in: '30s')
        described_class.schedule(scheduler)
      end

      it 'uses default interval when not configured' do
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'expiration_warnings' => {
              'enabled' => true
            }
          }
        })

        expect(scheduler).to receive(:every).with('1h', first_in: '30s')
        described_class.schedule(scheduler)
      end
    end

    context 'when disabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'expiration_warnings' => {
              'enabled' => false
            }
          }
        })
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:every)
        described_class.schedule(scheduler)
      end
    end

    context 'when config is missing' do
      before do
        allow(OT).to receive(:conf).and_return({})
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:every)
        described_class.schedule(scheduler)
      end
    end
  end

  describe '.process_expiring_secrets (via send)' do
    before do
      # Set up config
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {
            'enabled' => true,
            'warning_hours' => 24
          }
        }
      })

      # Mock Metadata class methods
      allow(Onetime::Metadata).to receive(:expiring_within).and_return([])
      allow(Onetime::Metadata).to receive(:warning_sent?).and_return(false)
      allow(Onetime::Metadata).to receive(:mark_warning_sent)
      allow(Onetime::Metadata).to receive(:cleanup_expired_from_timeline).and_return(0)
      allow(Onetime::Metadata).to receive(:load)

      # Mock Publisher
      allow(Onetime::Jobs::Publisher).to receive(:schedule_email)
    end

    it 'queries secrets expiring within warning window (24 hours)' do
      expect(Onetime::Metadata).to receive(:expiring_within).with(24 * 3600).and_return([])

      described_class.send(:process_expiring_secrets)
    end

    it 'skips secrets that already received warnings' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Metadata).to receive(:warning_sent?).with('meta123').and_return(true)

      expect(Onetime::Metadata).not_to receive(:load)

      described_class.send(:process_expiring_secrets)
    end

    it 'skips secrets that no longer exist' do
      non_existent_metadata = instance_double('Onetime::Metadata', exists?: false)

      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Metadata).to receive(:load).with('meta123').and_return(non_existent_metadata)

      expect(Onetime::Jobs::Publisher).not_to receive(:schedule_email)

      described_class.send(:process_expiring_secrets)
    end

    it 'skips anonymous secrets' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta456'])
      allow(Onetime::Metadata).to receive(:load).with('meta456').and_return(anonymous_metadata)

      expect(Onetime::Jobs::Publisher).not_to receive(:schedule_email)

      described_class.send(:process_expiring_secrets)
    end

    it 'skips secrets without owner email' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta789'])
      allow(Onetime::Metadata).to receive(:load).with('meta789').and_return(metadata_no_email)

      expect(Onetime::Jobs::Publisher).not_to receive(:schedule_email)

      described_class.send(:process_expiring_secrets)
    end

    it 'schedules warning email for valid secrets' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Metadata).to receive(:load).with('meta123').and_return(metadata_with_owner)

      expect(Onetime::Jobs::Publisher).to receive(:schedule_email).with(
        :expiration_warning,
        hash_including(
          recipient: 'owner@example.com',
          secret_key: 'abc123'
        ),
        hash_including(:delay_seconds)
      )

      described_class.send(:process_expiring_secrets)
    end

    it 'marks warning as sent after scheduling' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Metadata).to receive(:load).with('meta123').and_return(metadata_with_owner)

      expect(Onetime::Metadata).to receive(:mark_warning_sent).with('meta123')

      described_class.send(:process_expiring_secrets)
    end

    it 'calculates delay to send email WARNING_BUFFER_SECONDS before expiration' do
      fixed_now = Time.at(1_700_000_000) # Fixed timestamp to prevent flakiness
      allow(Familia).to receive(:now).and_return(fixed_now)

      metadata = instance_double(
        'Onetime::Metadata',
        identifier: 'meta123',
        exists?: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'abc123',
        secret_expiration: (fixed_now.to_i + 7200), # exactly 2 hours from fixed_now
        share_domain: nil
      )

      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Metadata).to receive(:load).with('meta123').and_return(metadata)

      expect(Onetime::Jobs::Publisher).to receive(:schedule_email) do |_template, _data, options|
        # Delay = seconds_until_expiry - WARNING_BUFFER_SECONDS = 7200 - 3600 = 3600
        expect(options[:delay_seconds]).to eq(described_class::WARNING_BUFFER_SECONDS)
      end

      described_class.send(:process_expiring_secrets)
    end

    it 'uses zero delay when less than WARNING_BUFFER_SECONDS remains' do
      fixed_now = Time.at(1_700_000_000) # Fixed timestamp to prevent flakiness
      allow(Familia).to receive(:now).and_return(fixed_now)

      soon_metadata = instance_double(
        'Onetime::Metadata',
        identifier: 'soon123',
        exists?: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'xyz789',
        secret_expiration: (fixed_now.to_i + 1800), # 30 minutes from fixed_now
        share_domain: 'custom.example.com'
      )

      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['soon123'])
      allow(Onetime::Metadata).to receive(:load).with('soon123').and_return(soon_metadata)

      expect(Onetime::Jobs::Publisher).to receive(:schedule_email) do |_template, _data, options|
        expect(options[:delay_seconds]).to eq(0)
      end

      described_class.send(:process_expiring_secrets)
    end

    it 'cleans up expired timeline entries' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return([])

      expect(Onetime::Metadata).to receive(:cleanup_expired_from_timeline)
        .with(be_within(60).of(Familia.now.to_f - described_class::CLEANUP_GRACE_PERIOD_SECONDS))
        .and_return(5)

      described_class.send(:process_expiring_secrets)
    end

    it 'includes share_domain in email data' do
      metadata_with_domain = instance_double(
        'Onetime::Metadata',
        identifier: 'meta_domain',
        exists?: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'dom456',
        secret_expiration: (Familia.now.to_i + 7200),
        share_domain: 'secrets.example.com'
      )

      allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta_domain'])
      allow(Onetime::Metadata).to receive(:load).with('meta_domain').and_return(metadata_with_domain)

      expect(Onetime::Jobs::Publisher).to receive(:schedule_email).with(
        :expiration_warning,
        hash_including(share_domain: 'secrets.example.com'),
        anything
      )

      described_class.send(:process_expiring_secrets)
    end

    context 'when scheduling fails' do
      it 'does not mark warning as sent on failure' do
        allow(Onetime::Metadata).to receive(:expiring_within).and_return(['meta123'])
        allow(Onetime::Metadata).to receive(:load).with('meta123').and_return(metadata_with_owner)
        allow(Onetime::Jobs::Publisher).to receive(:schedule_email).and_raise(StandardError, 'Connection error')

        described_class.send(:process_expiring_secrets)

        # Should NOT mark as sent when scheduling fails (allows retry on next run)
        expect(Onetime::Metadata).not_to have_received(:mark_warning_sent).with('meta123')
      end

      it 'continues processing remaining secrets after failure' do
        metadata2 = instance_double(
          'Onetime::Metadata',
          identifier: 'meta_second',
          exists?: true,
          anonymous?: false,
          load_owner: owner_with_email,
          secret_shortid: 'second789',
          secret_expiration: (Familia.now.to_i + 7200),
          share_domain: nil
        )

        allow(Onetime::Metadata).to receive(:expiring_within).and_return(%w[meta123 meta_second])
        allow(Onetime::Metadata).to receive(:load).with('meta123').and_return(metadata_with_owner)
        allow(Onetime::Metadata).to receive(:load).with('meta_second').and_return(metadata2)

        # First call raises, second should succeed
        call_count = 0
        allow(Onetime::Jobs::Publisher).to receive(:schedule_email) do
          call_count += 1
          raise StandardError, 'Connection error' if call_count == 1
        end

        # Should not raise, should continue to second secret
        expect { described_class.send(:process_expiring_secrets) }.not_to raise_error

        # First secret should NOT be marked (failed)
        expect(Onetime::Metadata).not_to have_received(:mark_warning_sent).with('meta123')
        # Second secret should be marked (succeeded)
        expect(Onetime::Metadata).to have_received(:mark_warning_sent).with('meta_second')
      end
    end
  end

  describe 'warning_hours configuration' do
    it 'returns configured value' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {
            'warning_hours' => 48
          }
        }
      })

      expect(described_class.send(:warning_hours)).to eq(48)
    end

    it 'defaults to 24 when not configured' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {}
        }
      })

      expect(described_class.send(:warning_hours)).to eq(24)
    end

    it 'defaults to 24 when configured as 0' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {
            'warning_hours' => 0
          }
        }
      })

      expect(described_class.send(:warning_hours)).to eq(24)
    end
  end

  describe 'batch_size configuration' do
    it 'returns configured value' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {
            'batch_size' => 200
          }
        }
      })

      expect(described_class.send(:batch_size)).to eq(200)
    end

    it 'defaults to DEFAULT_BATCH_SIZE when not configured' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {}
        }
      })

      expect(described_class.send(:batch_size)).to eq(described_class::DEFAULT_BATCH_SIZE)
    end

    it 'defaults to DEFAULT_BATCH_SIZE when configured as 0' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {
            'batch_size' => 0
          }
        }
      })

      expect(described_class.send(:batch_size)).to eq(described_class::DEFAULT_BATCH_SIZE)
    end
  end

  describe 'batch limiting (rate limiting)' do
    before do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'expiration_warnings' => {
            'enabled' => true,
            'warning_hours' => 24,
            'batch_size' => 2
          }
        }
      })

      allow(Onetime::Metadata).to receive(:warning_sent?).and_return(false)
      allow(Onetime::Metadata).to receive(:mark_warning_sent)
      allow(Onetime::Metadata).to receive(:cleanup_expired_from_timeline).and_return(0)
      allow(Onetime::Jobs::Publisher).to receive(:schedule_email)
    end

    let(:metadata1) do
      instance_double(
        'Onetime::Metadata',
        identifier: 'meta1',
        exists?: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'key1',
        secret_expiration: (Familia.now.to_i + 7200),
        share_domain: nil
      )
    end

    let(:metadata2) do
      instance_double(
        'Onetime::Metadata',
        identifier: 'meta2',
        exists?: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'key2',
        secret_expiration: (Familia.now.to_i + 7200),
        share_domain: nil
      )
    end

    let(:metadata3) do
      instance_double(
        'Onetime::Metadata',
        identifier: 'meta3',
        exists?: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'key3',
        secret_expiration: (Familia.now.to_i + 7200),
        share_domain: nil
      )
    end

    it 'limits processing to batch_size secrets' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(%w[meta1 meta2 meta3])
      allow(Onetime::Metadata).to receive(:load).with('meta1').and_return(metadata1)
      allow(Onetime::Metadata).to receive(:load).with('meta2').and_return(metadata2)
      allow(Onetime::Metadata).to receive(:load).with('meta3').and_return(metadata3)

      described_class.send(:process_expiring_secrets)

      # Only first 2 (batch_size) should be processed
      expect(Onetime::Jobs::Publisher).to have_received(:schedule_email).exactly(2).times
      expect(Onetime::Metadata).to have_received(:mark_warning_sent).with('meta1')
      expect(Onetime::Metadata).to have_received(:mark_warning_sent).with('meta2')
      expect(Onetime::Metadata).not_to have_received(:mark_warning_sent).with('meta3')
    end

    it 'does not throttle when under batch_size' do
      allow(Onetime::Metadata).to receive(:expiring_within).and_return(%w[meta1])
      allow(Onetime::Metadata).to receive(:load).with('meta1').and_return(metadata1)

      described_class.send(:process_expiring_secrets)

      expect(Onetime::Jobs::Publisher).to have_received(:schedule_email).exactly(1).time
    end
  end
end
