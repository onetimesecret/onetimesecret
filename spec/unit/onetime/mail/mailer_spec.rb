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
end
