# spec/unit/onetime/jobs/scheduled/expiration_warning_job_spec.rb
#
# frozen_string_literal: true

# ExpirationWarningJob Test Suite
#
# Tests the scheduled job that scans for expiring secrets and enqueues
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
#      - Tests warning email enqueuing (immediate, no delay: #4844)
#      - Tests timeline cleanup
#
# Setup Requirements:
#   - Mocked OT.conf for configuration
#   - Mocked Receipt class methods
#   - Mocked Publisher.enqueue_email
#
# Run with: pnpm run test:rspec spec/onetime/jobs/scheduled/expiration_warning_job_spec.rb

require 'spec_helper'
require 'rufus-scheduler'
require 'onetime/jobs/scheduled/expiration_warning_job'
require 'onetime/jobs/publisher'

RSpec.describe Onetime::Jobs::Scheduled::ExpirationWarningJob do
  let(:scheduler) { instance_double(Rufus::Scheduler) }

  # Mock owner with email
  let(:owner_with_email) do
    instance_double('Onetime::Customer', email: 'owner@example.com', locale: 'de', verified?: true)
  end

  # Mock owner without email
  let(:owner_without_email) do
    instance_double('Onetime::Customer', email: nil, locale: nil)
  end

  # The receipt's secret: still stored, not an account verification link.
  let(:live_secret) { instance_double('Onetime::Secret', verification?: false) }

  # Mock metadata with owner
  let(:metadata_with_owner) do
    instance_double(
      'Onetime::Receipt',
      identifier: 'meta123',
      exists?: true,
      live?: true,
      load_secret: live_secret,
      sender_domain_id: nil,
      shortid: 'shortrcp',
      unregister_from_expiration_notifications: true,
      anonymous?: false,
      load_owner: owner_with_email,
      secret_shortid: 'abc123',
      secret_expiration: (Familia.now.to_i + 7200), # 2 hours from now
    )
  end

  # Mock anonymous metadata
  let(:anonymous_metadata) do
    instance_double(
      'Onetime::Receipt',
      identifier: 'meta456',
      exists?: true,
      live?: true,
      load_secret: live_secret,
      sender_domain_id: nil,
      shortid: 'shortrcp',
      unregister_from_expiration_notifications: true,
      anonymous?: true
    )
  end

  # Mock metadata without owner email
  let(:metadata_no_email) do
    instance_double(
      'Onetime::Receipt',
      identifier: 'meta789',
      exists?: true,
      live?: true,
      load_secret: live_secret,
      sender_domain_id: nil,
      shortid: 'shortrcp',
      unregister_from_expiration_notifications: true,
      anonymous?: false,
      load_owner: owner_without_email
    )
  end

  describe '.schedule' do
    context 'when enabled' do
      before do
        allow(OT).to receive(:conf).and_return(OT::Config.wrap({
          'jobs' => {
            'expiration_warnings' => {
              'enabled' => true,
              'check_interval' => '1h'
            }
          }
        }))
      end

      it 'registers an interval job with the scheduler' do
        expect(scheduler).to receive(:every).with('1h', first_in: '30s')
        described_class.schedule(scheduler)
      end

      it 'uses default interval when not configured' do
        allow(OT).to receive(:conf).and_return(OT::Config.wrap({
          'jobs' => {
            'expiration_warnings' => {
              'enabled' => true
            }
          }
        }))

        expect(scheduler).to receive(:every).with('1h', first_in: '30s')
        described_class.schedule(scheduler)
      end
    end

    context 'when disabled' do
      before do
        allow(OT).to receive(:conf).and_return(OT::Config.wrap({
          'jobs' => {
            'expiration_warnings' => {
              'enabled' => false
            }
          }
        }))
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:every)
        described_class.schedule(scheduler)
      end
    end

    context 'when the settings are unset' do
      before do
        allow(OT).to receive(:conf).and_return(OT::Config.wrap({ 'jobs' => { 'expiration_warnings' => { 'enabled' => nil } } }))
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:every)
        described_class.schedule(scheduler)
      end
    end
  end

  describe '.process_expiring_secrets (via send)' do
    # Note: SemanticLogger flush is handled globally in spec_helper.rb after(:each)
    # using synchronous mode (SemanticLogger.sync!) which eliminates async race conditions.

    before do
      # Set up config
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => {
            'enabled' => true,
            'warning_hours' => 24,
            'batch_size' => nil
          }
        }
      }))

      # Mock Receipt class methods
      allow(Onetime::Receipt).to receive(:expiring_within).and_return([])
      allow(Onetime::Receipt).to receive(:warning_sent?).and_return(false)
      allow(Onetime::Receipt).to receive(:mark_warning_sent)
      allow(Onetime::Receipt).to receive(:cleanup_expired_from_timeline).and_return(0)
      allow(Onetime::Receipt).to receive(:load)

      # Mock Publisher
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)
    end

    it 'queries secrets expiring within warning window (24 hours)' do
      expect(Onetime::Receipt).to receive(:expiring_within).with(24 * 3600).and_return([])

      described_class.send(:process_expiring_secrets)
    end

    it 'skips secrets that already received warnings' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Receipt).to receive(:warning_sent?).with('meta123').and_return(true)

      expect(Onetime::Receipt).not_to receive(:load)

      described_class.send(:process_expiring_secrets)
    end

    it 'skips secrets that no longer exist' do
      non_existent_metadata = instance_double('Onetime::Receipt', exists?: false)

      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(non_existent_metadata)

      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

      described_class.send(:process_expiring_secrets)
    end

    it 'skips anonymous secrets and drops their timeline entry' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta456'])
      allow(Onetime::Receipt).to receive(:load).with('meta456').and_return(anonymous_metadata)

      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

      described_class.send(:process_expiring_secrets)

      expect(anonymous_metadata).to have_received(:unregister_from_expiration_notifications)
    end

    # The permanent skips drop the entry, so it stops taking a batch slot.
    # A receipt whose owner has no email is skipped but kept: the owner can
    # still add one.
    it 'keeps the entry of a receipt whose owner has no email' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta789'])
      allow(Onetime::Receipt).to receive(:load).with('meta789').and_return(metadata_no_email)

      described_class.send(:process_expiring_secrets)

      expect(metadata_no_email).not_to have_received(:unregister_from_expiration_notifications)
    end

    it 'gives freed batch slots to due warnings on the next scan' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => { 'expiration_warnings' => { 'enabled' => true, 'warning_hours' => 24, 'batch_size' => 1 } },
      }))
      timeline = %w[meta456 meta123]
      allow(Onetime::Receipt).to receive(:expiring_within) { timeline.dup }
      allow(Onetime::Receipt).to receive(:load).with('meta456').and_return(anonymous_metadata)
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)
      allow(anonymous_metadata).to receive(:unregister_from_expiration_notifications) { timeline.delete('meta456') }

      described_class.send(:process_expiring_secrets)
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)

      described_class.send(:process_expiring_secrets)
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(:expiration_warning, anything, domain_id: nil)
    end

    # Mail goes only to a verified owner. The skip is permanent, like the
    # anonymous one, so the entry is dropped and stops taking a batch slot.
    context 'when the owner is not verified' do
      let(:unverified_owner) do
        instance_double('Onetime::Customer', email: 'unverified@example.com', locale: 'de', verified?: false)
      end

      let(:unverified_receipt) do
        instance_double(
          'Onetime::Receipt',
          identifier: 'meta_unv',
          exists?: true,
          live?: true,
          load_secret: live_secret,
          sender_domain_id: nil,
          shortid: 'shortunv',
          unregister_from_expiration_notifications: true,
          anonymous?: false,
          load_owner: unverified_owner,
          secret_shortid: 'unv12345',
          secret_expiration: (Familia.now.to_i + 7200),
        )
      end

      it 'sends nothing, does not mark it warned, and drops the timeline entry' do
        allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta_unv'])
        allow(Onetime::Receipt).to receive(:load).with('meta_unv').and_return(unverified_receipt)

        described_class.send(:process_expiring_secrets)

        expect(unverified_owner).to have_received(:verified?)
        expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
        expect(Onetime::Receipt).not_to have_received(:mark_warning_sent)
        expect(unverified_receipt).to have_received(:unregister_from_expiration_notifications)
      end

      it 'gives the freed batch slot to a due warning on the next scan' do
        allow(OT).to receive(:conf).and_return(OT::Config.wrap({
          'jobs' => { 'expiration_warnings' => { 'enabled' => true, 'warning_hours' => 24, 'batch_size' => 1 } },
        }))
        timeline = %w[meta_unv meta123]
        allow(Onetime::Receipt).to receive(:expiring_within) { timeline.dup }
        allow(Onetime::Receipt).to receive(:load).with('meta_unv').and_return(unverified_receipt)
        allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)
        allow(unverified_receipt).to receive(:unregister_from_expiration_notifications) { timeline.delete('meta_unv') }

        described_class.send(:process_expiring_secrets)
        expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)

        described_class.send(:process_expiring_secrets)
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email)
          .once.with(:expiration_warning, hash_including(recipient: 'owner@example.com'), domain_id: nil)
      end
    end

    it 'skips secrets without owner email' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta789'])
      allow(Onetime::Receipt).to receive(:load).with('meta789').and_return(metadata_no_email)

      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

      described_class.send(:process_expiring_secrets)
    end

    # The payload is an account notification: the secret's short id under
    # its own name, nothing that resolves. The short id used to travel as
    # secret_key and was built into /secret/<short id>: the page shell opened
    # but the lookup behind it failed, an 8-character prefix not being a
    # secret identifier. A receipt identifier would be a bearer capability.
    it 'enqueues the warning email for valid secrets with the secret short id only' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)

      expect(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, *rest|
        expect(template).to eq(:expiration_warning)
        expect(data).to include(recipient: 'owner@example.com', secret_shortid: 'abc123')
        expect(data.keys).to contain_exactly(:recipient, :secret_shortid, :expires_at, :locale)
        expect(rest).to eq([{ domain_id: nil }])
      end

      described_class.send(:process_expiring_secrets)
    end

    it 'marks warning as sent after enqueuing' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)

      expect(Onetime::Receipt).to receive(:mark_warning_sent).with('meta123')

      described_class.send(:process_expiring_secrets)
    end

    # No delayed delivery. The job used to pass delay_seconds to
    # Publisher.schedule_email, which published to email.message.schedule, a
    # queue nothing consumed: with jobs enabled the warning expired into the
    # DLQ and was discarded (#4844). The warning now goes out on the scan
    # that finds the secret inside the warning window, on the queue
    # EmailWorker reads.
    it 'enqueues for immediate delivery, with no delay option' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)

      expect(Onetime::Jobs::Publisher).to receive(:enqueue_email).with(:expiration_warning, kind_of(Hash), domain_id: nil)
      expect(Onetime::Jobs::Publisher).not_to respond_to(:schedule_email)

      described_class.send(:process_expiring_secrets)
    end

    it 'cleans up expired timeline entries' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return([])

      expect(Onetime::Receipt).to receive(:cleanup_expired_from_timeline)
        .with(be_within(60).of(Familia.now.to_f - described_class::CLEANUP_GRACE_PERIOD_SECONDS))
        .and_return(5)

      described_class.send(:process_expiring_secrets)
    end

    # The email links to the canonical host, where the owner signs in, so
    # the domain the secret was shared from is not part of the payload.
    it 'does not include share_domain or any identifier in email data' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)

      expect(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |_template, data|
        expect(data).not_to include(:share_domain, :receipt_identifier, :secret_key)
      end

      described_class.send(:process_expiring_secrets)
    end

    # A reveal or burn takes the receipt off the timeline, but entries
    # written before that (or left by a failed removal) remain. The job
    # skips any receipt whose secret is no longer live and drops the entry.
    context 'when the receipt is no longer live' do
      let(:consumed_receipt) do
        instance_double(
          'Onetime::Receipt',
          identifier: 'meta_done',
          exists?: true,
          live?: false,
          unregister_from_expiration_notifications: true,
        )
      end

      before do
        allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta_done'])
        allow(Onetime::Receipt).to receive(:load).with('meta_done').and_return(consumed_receipt)
      end

      it 'sends nothing, does not mark it warned, and removes it from the timeline' do
        expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

        described_class.send(:process_expiring_secrets)

        expect(consumed_receipt).to have_received(:unregister_from_expiration_notifications)
        expect(Onetime::Receipt).not_to have_received(:mark_warning_sent)
      end
    end

    context "when the receipt's secret is an account verification link" do
      let(:live_secret) { instance_double('Onetime::Secret', verification?: true) }

      it 'sends nothing and drops the timeline entry' do
        allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
        allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)

        expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

        described_class.send(:process_expiring_secrets)

        expect(metadata_with_owner).to have_received(:unregister_from_expiration_notifications)
      end
    end

    context "when the receipt's secret is already gone" do
      let(:live_secret) { nil }

      it 'sends nothing and drops the timeline entry' do
        allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
        allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)

        expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

        described_class.send(:process_expiring_secrets)

        expect(metadata_with_owner).to have_received(:unregister_from_expiration_notifications)
      end
    end

    # Sender and language: the receipt's validated stored domain_id
    # (Receipt#sender_domain_id, tested in secret_reveal_notice_spec.rb),
    # and the owner's locale with the default as fallback.
    context 'sender domain and locale' do
      let(:shared_receipt) do
        instance_double(
          'Onetime::Receipt',
          identifier: 'meta_dom',
          exists?: true,
          live?: true,
          load_secret: live_secret,
          sender_domain_id: 'cd-acme',
          shortid: 'meta_dom',
          anonymous?: false,
          load_owner: owner,
          secret_shortid: 'dom12345',
          secret_expiration: (Familia.now.to_i + 7200),
        )
      end

      before do
        allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta_dom'])
        allow(Onetime::Receipt).to receive(:load).with('meta_dom').and_return(shared_receipt)
      end

      context 'with an owner locale' do
        let(:owner) { instance_double('Onetime::Customer', email: 'owner@example.com', locale: 'fr', verified?: true) }

        it 'passes the custom domain id and the owner locale' do
          expect(Onetime::Jobs::Publisher).to receive(:enqueue_email)
            .with(:expiration_warning, hash_including(locale: 'fr'), domain_id: 'cd-acme')

          described_class.send(:process_expiring_secrets)
        end

        it 'keeps share_domain out of the payload' do
          expect(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |_template, data, **|
            expect(data).not_to include(:share_domain)
          end

          described_class.send(:process_expiring_secrets)
        end
      end

      context 'with a blank owner locale' do
        let(:owner) { instance_double('Onetime::Customer', email: 'owner@example.com', locale: '', verified?: true) }

        it 'falls back to the default locale' do
          expect(Onetime::Jobs::Publisher).to receive(:enqueue_email)
            .with(:expiration_warning, hash_including(locale: OT.default_locale), domain_id: 'cd-acme')

          described_class.send(:process_expiring_secrets)
        end
      end
    end

    # The receipt identifier is a bearer capability (the receipt route
    # answers without an ownership check): logs name it by its short id.
    it 'logs the receipt short id, never its identifier' do
      lines  = []
      logger = double('scheduler logger')
      %i[debug info warn error].each { |level| allow(logger).to receive(level) { |msg, *| lines << msg.to_s } }
      allow(described_class).to receive(:scheduler_logger).and_return(logger)
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(%w[meta123 meta_second])
      failing = instance_double(
        'Onetime::Receipt',
        identifier: 'meta_second', shortid: 'shortfal', exists?: true, live?: true,
        load_secret: live_secret, sender_domain_id: nil, anonymous?: false,
        load_owner: owner_with_email, secret_shortid: 'second78',
        secret_expiration: (Familia.now.to_i + 7200)
      )
      allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)
      allow(Onetime::Receipt).to receive(:load).with('meta_second').and_return(failing)
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |_template, data, **|
        raise StandardError, 'Connection error' if data[:secret_shortid] == 'second78'

        true
      end

      described_class.send(:process_expiring_secrets)

      expect(lines.join("\n")).to include('shortrcp', 'shortfal')
      expect(lines.join("\n")).not_to include('meta123', 'meta_second')
    end

    context 'when enqueuing fails' do
      it 'does not mark warning as sent on failure' do
        allow(Onetime::Receipt).to receive(:expiring_within).and_return(['meta123'])
        allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_raise(StandardError, 'Connection error')

        described_class.send(:process_expiring_secrets)

        # Should NOT mark as sent when enqueuing fails (allows retry on next run)
        expect(Onetime::Receipt).not_to have_received(:mark_warning_sent).with('meta123')
      end

      it 'continues processing remaining secrets after failure' do
        metadata2 = instance_double(
          'Onetime::Receipt',
          identifier: 'meta_second',
          exists?: true,
          live?: true,
          load_secret: live_secret,
          sender_domain_id: nil,
          shortid: 'shortrcp',
          unregister_from_expiration_notifications: true,
          anonymous?: false,
          load_owner: owner_with_email,
          secret_shortid: 'second789',
          secret_expiration: (Familia.now.to_i + 7200),
        )

        allow(Onetime::Receipt).to receive(:expiring_within).and_return(%w[meta123 meta_second])
        allow(Onetime::Receipt).to receive(:load).with('meta123').and_return(metadata_with_owner)
        allow(Onetime::Receipt).to receive(:load).with('meta_second').and_return(metadata2)

        # First call raises, second should succeed
        call_count = 0
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do
          call_count += 1
          raise StandardError, 'Connection error' if call_count == 1
        end

        # Should not raise, should continue to second secret
        expect { described_class.send(:process_expiring_secrets) }.not_to raise_error

        # First secret should NOT be marked (failed)
        expect(Onetime::Receipt).not_to have_received(:mark_warning_sent).with('meta123')
        # Second secret should be marked (succeeded)
        expect(Onetime::Receipt).to have_received(:mark_warning_sent).with('meta_second')
      end
    end
  end

  describe 'warning_hours configuration' do
    it 'returns configured value' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => {
            'warning_hours' => 48
          }
        }
      }))

      expect(described_class.send(:warning_hours)).to eq(48)
    end

    it 'defaults to 24 when not configured' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => { 'warning_hours' => nil }
        }
      }))

      expect(described_class.send(:warning_hours)).to eq(24)
    end

    it 'defaults to 24 when configured as 0' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => {
            'warning_hours' => 0
          }
        }
      }))

      expect(described_class.send(:warning_hours)).to eq(24)
    end
  end

  describe 'batch_size configuration' do
    it 'returns configured value' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => {
            'batch_size' => 200
          }
        }
      }))

      expect(described_class.send(:batch_size)).to eq(200)
    end

    it 'defaults to DEFAULT_BATCH_SIZE when not configured' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => { 'batch_size' => nil }
        }
      }))

      expect(described_class.send(:batch_size)).to eq(described_class::DEFAULT_BATCH_SIZE)
    end

    it 'defaults to DEFAULT_BATCH_SIZE when configured as 0' do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => {
            'batch_size' => 0
          }
        }
      }))

      expect(described_class.send(:batch_size)).to eq(described_class::DEFAULT_BATCH_SIZE)
    end
  end

  describe 'batch limiting (rate limiting)' do
    before do
      allow(OT).to receive(:conf).and_return(OT::Config.wrap({
        'jobs' => {
          'expiration_warnings' => {
            'enabled' => true,
            'warning_hours' => 24,
            'batch_size' => 2
          }
        }
      }))

      allow(Onetime::Receipt).to receive(:warning_sent?).and_return(false)
      allow(Onetime::Receipt).to receive(:mark_warning_sent)
      allow(Onetime::Receipt).to receive(:cleanup_expired_from_timeline).and_return(0)
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)
    end

    let(:metadata1) do
      instance_double(
        'Onetime::Receipt',
        identifier: 'meta1',
        exists?: true,
        live?: true,
        load_secret: live_secret,
        sender_domain_id: nil,
        shortid: 'shortrcp',
        unregister_from_expiration_notifications: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'key1',
        secret_expiration: (Familia.now.to_i + 7200),
      )
    end

    let(:metadata2) do
      instance_double(
        'Onetime::Receipt',
        identifier: 'meta2',
        exists?: true,
        live?: true,
        load_secret: live_secret,
        sender_domain_id: nil,
        shortid: 'shortrcp',
        unregister_from_expiration_notifications: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'key2',
        secret_expiration: (Familia.now.to_i + 7200),
      )
    end

    let(:metadata3) do
      instance_double(
        'Onetime::Receipt',
        identifier: 'meta3',
        exists?: true,
        live?: true,
        load_secret: live_secret,
        sender_domain_id: nil,
        shortid: 'shortrcp',
        unregister_from_expiration_notifications: true,
        anonymous?: false,
        load_owner: owner_with_email,
        secret_shortid: 'key3',
        secret_expiration: (Familia.now.to_i + 7200),
      )
    end

    it 'limits processing to batch_size secrets' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(%w[meta1 meta2 meta3])
      allow(Onetime::Receipt).to receive(:load).with('meta1').and_return(metadata1)
      allow(Onetime::Receipt).to receive(:load).with('meta2').and_return(metadata2)
      allow(Onetime::Receipt).to receive(:load).with('meta3').and_return(metadata3)

      described_class.send(:process_expiring_secrets)

      # Only first 2 (batch_size) should be processed
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).exactly(2).times
      expect(Onetime::Receipt).to have_received(:mark_warning_sent).with('meta1')
      expect(Onetime::Receipt).to have_received(:mark_warning_sent).with('meta2')
      expect(Onetime::Receipt).not_to have_received(:mark_warning_sent).with('meta3')
    end

    it 'does not throttle when under batch_size' do
      allow(Onetime::Receipt).to receive(:expiring_within).and_return(%w[meta1])
      allow(Onetime::Receipt).to receive(:load).with('meta1').and_return(metadata1)

      described_class.send(:process_expiring_secrets)

      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).exactly(1).time
    end
  end
end
