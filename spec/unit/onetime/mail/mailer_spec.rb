# spec/unit/onetime/mail/mailer_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'

RSpec.describe Onetime::Mail::Mailer do
  after { described_class.reset! }

  describe '.determine_provider (auto-detection)' do
    subject { described_class.send(:determine_provider) }

    before do
      allow(described_class).to receive(:emailer_config).and_return(config)
      # Prevent RACK_ENV=test from short-circuiting auto-detection
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RACK_ENV').and_return('development')
    end

    context 'when explicit mode is set' do
      let(:config) { { 'mode' => 'smtp', 'host' => 'mail.example.com' } }

      it 'uses the explicit mode' do
        expect(subject).to eq('smtp')
      end
    end

    context 'when no mode is set and region + user present' do
      let(:config) { { 'region' => 'us-east-1', 'user' => 'AKID' } }

      it 'auto-detects SES' do
        expect(subject).to eq('ses')
      end
    end

    context 'when no mode is set and sendgrid_api_key present' do
      let(:config) { { 'sendgrid_api_key' => 'SG.test' } }

      it 'auto-detects SendGrid' do
        expect(subject).to eq('sendgrid')
      end
    end

    context 'when no mode is set and host present' do
      let(:config) { { 'host' => 'smtp.example.com' } }

      it 'auto-detects SMTP' do
        expect(subject).to eq('smtp')
      end
    end

    context 'when no mode and no config hints' do
      let(:config) { {} }

      it 'falls back to logger' do
        expect(subject).to eq('logger')
      end
    end

    context 'when RACK_ENV is test and no mode set' do
      let(:config) { {} }

      it 'returns logger regardless of config hints' do
        allow(ENV).to receive(:[]).with('RACK_ENV').and_return('test')
        expect(subject).to eq('logger')
      end
    end
  end

  # ==========================================================================
  # Sender Config (per-domain email identity) Tests
  # ==========================================================================
  # These tests verify that Mailer correctly uses sender_config when provided,
  # falling back to global defaults when config is nil, not enabled, or not
  # verified.
  # ==========================================================================

  describe 'sender_config support' do
    let(:global_from) { 'global@example.com' }
    let(:global_reply_to) { nil }

    let(:mock_sender_config) do
      instance_double(
        Onetime::CustomDomain::MailerConfig,
        domain_id: 'dom_test123',
        from_address: 'custom@acme.example.com',
        from_name: 'Acme Secrets',
        reply_to: 'support@acme.example.com',
        provider: 'ses',
        enabled?: true,
        verified?: true,
        api_key: 'test-api-key-ses'
      )
    end

    let(:mock_template) do
      instance_double(
        Onetime::Mail::Templates::SecretLink,
        to_email: { to: 'user@example.com', from: global_from, subject: 'Test', text_body: 'body' },
        data: { sender_email: 'sender@example.com' }
      )
    end

    let(:mock_backend) do
      instance_double(Onetime::Mail::Delivery::Logger, deliver: { status: 'logged' })
    end

    before do
      allow(described_class).to receive(:emailer_config).and_return({ 'mode' => 'logger', 'from' => global_from })
      allow(described_class).to receive(:delivery_backend).and_return(mock_backend)
    end

    describe '.deliver' do
      before do
        allow(described_class).to receive(:template_class_for).and_return(Onetime::Mail::Templates::SecretLink)
        allow(Onetime::Mail::Templates::SecretLink).to receive(:new).and_return(mock_template)
        allow(described_class).to receive(:deliver_template).and_return({ status: 'logged' })
      end

      it 'passes sender_config through to deliver_template' do
        described_class.deliver(:secret_link, { recipient: 'user@example.com' }, sender_config: mock_sender_config)

        expect(described_class).to have_received(:deliver_template).with(mock_template, sender_config: mock_sender_config)
      end

      it 'passes nil sender_config when not provided' do
        described_class.deliver(:secret_link, { recipient: 'user@example.com' })

        expect(described_class).to have_received(:deliver_template).with(mock_template, sender_config: nil)
      end
    end

    describe '.deliver_template' do
      before do
        # Allow resolve_backend to be called through
        allow(described_class).to receive(:resolve_backend).and_return(mock_backend)
      end

      context 'when sender_config is enabled and verified' do
        it 'uses sender_config from_address in the email' do
          allow(mock_template).to receive(:to_email) do |from:, reply_to:|
            expect(from).to eq('custom@acme.example.com')
            { to: 'user@example.com', from: from, subject: 'Test', text_body: 'body' }
          end

          described_class.deliver_template(mock_template, sender_config: mock_sender_config)

          expect(mock_backend).to have_received(:deliver)
        end

        it 'uses sender_config reply_to in the email' do
          allow(mock_template).to receive(:to_email) do |from:, reply_to:|
            expect(reply_to).to eq('support@acme.example.com')
            { to: 'user@example.com', from: from, subject: 'Test', text_body: 'body' }
          end

          described_class.deliver_template(mock_template, sender_config: mock_sender_config)
        end
      end

      context 'when sender_config is nil' do
        it 'uses global from_address' do
          allow(mock_template).to receive(:to_email) do |from:, reply_to:|
            expect(from).to eq(global_from)
            { to: 'user@example.com', from: from, subject: 'Test', text_body: 'body' }
          end

          described_class.deliver_template(mock_template, sender_config: nil)
        end
      end

      context 'when sender_config is not verified' do
        let(:unverified_config) do
          instance_double(
            Onetime::CustomDomain::MailerConfig,
            domain_id: 'dom_unverified',
            from_address: 'custom@unverified.example.com',
            from_name: 'Unverified',
            reply_to: nil,
            provider: 'ses',
            enabled?: true,
            verified?: false,
            api_key: nil
          )
        end

        it 'falls back to global from_address' do
          allow(mock_template).to receive(:to_email) do |from:, reply_to:|
            expect(from).to eq(global_from)
            { to: 'user@example.com', from: from, subject: 'Test', text_body: 'body' }
          end

          described_class.deliver_template(mock_template, sender_config: unverified_config)
        end
      end

      context 'when sender_config is not enabled' do
        let(:disabled_config) do
          instance_double(
            Onetime::CustomDomain::MailerConfig,
            domain_id: 'dom_disabled',
            from_address: 'custom@disabled.example.com',
            from_name: 'Disabled',
            reply_to: nil,
            provider: 'ses',
            enabled?: false,
            verified?: true,
            api_key: nil
          )
        end

        it 'falls back to global from_address' do
          allow(mock_template).to receive(:to_email) do |from:, reply_to:|
            expect(from).to eq(global_from)
            { to: 'user@example.com', from: from, subject: 'Test', text_body: 'body' }
          end

          described_class.deliver_template(mock_template, sender_config: disabled_config)
        end
      end
    end

    describe '.resolve_backend' do
      it 'returns global backend when sender_config is nil' do
        result = described_class.send(:resolve_backend, nil)

        expect(result).to eq(mock_backend)
      end

      context 'when sender_config is enabled and verified' do
        let(:domain_backend) do
          instance_double(Onetime::Mail::Delivery::Logger, deliver: { status: 'logged' })
        end

        before do
          allow(described_class).to receive(:create_backend_for).and_return(domain_backend)
        end

        it 'creates a per-domain backend' do
          result = described_class.send(:resolve_backend, mock_sender_config)

          expect(result).to eq(domain_backend)
          expect(described_class).to have_received(:create_backend_for).with(mock_sender_config)
        end

        it 'caches per-domain backends by domain_id' do
          result1 = described_class.send(:resolve_backend, mock_sender_config)
          result2 = described_class.send(:resolve_backend, mock_sender_config)

          expect(result1).to equal(result2)
          expect(described_class).to have_received(:create_backend_for).once
        end
      end

      context 'when sender_config is not enabled' do
        let(:disabled_config) do
          instance_double(
            Onetime::CustomDomain::MailerConfig,
            domain_id: 'dom_disabled',
            enabled?: false,
            verified?: true
          )
        end

        it 'returns global backend' do
          result = described_class.send(:resolve_backend, disabled_config)

          expect(result).to eq(mock_backend)
        end
      end

      context 'when sender_config is not verified' do
        let(:unverified_config) do
          instance_double(
            Onetime::CustomDomain::MailerConfig,
            domain_id: 'dom_unverified',
            enabled?: true,
            verified?: false
          )
        end

        it 'returns global backend' do
          result = described_class.send(:resolve_backend, unverified_config)

          expect(result).to eq(mock_backend)
        end
      end
    end

    describe '.reset!' do
      it 'clears domain backend cache' do
        domain_backend = instance_double(Onetime::Mail::Delivery::Logger, deliver: { status: 'logged' })
        allow(described_class).to receive(:create_backend_for).and_return(domain_backend)

        # Prime the cache
        described_class.send(:resolve_backend, mock_sender_config)

        # Reset should clear it
        described_class.reset!

        # After reset, create_backend_for should be called again
        allow(described_class).to receive(:delivery_backend).and_return(mock_backend)
        described_class.send(:resolve_backend, mock_sender_config)

        expect(described_class).to have_received(:create_backend_for).twice
      end
    end
  end
end
