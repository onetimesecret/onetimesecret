# spec/onetime/jobs/workers/email_worker_spec.rb
#
# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/onetime/jobs/workers/email_worker'

RSpec.describe Onetime::Jobs::Workers::EmailWorker do
  describe 'class configuration' do
    it 'is defined as a class' do
      expect(described_class).to be_a(Class)
    end

    it 'includes BaseWorker' do
      expect(described_class.included_modules)
        .to include(Onetime::Jobs::Workers::BaseWorker)
    end

    it 'has queue_name set to email.immediate' do
      expect(described_class.queue_name).to eq('email.immediate')
    end
  end

  describe '#perform' do
    subject(:worker) { described_class.new }

    let(:message) do
      {
        'template' => 'welcome',
        'data' => {
          'email_address' => 'test@example.com',
          'secret' => 'abc123'
        }
      }
    end

    before do
      allow(Onetime::Mail).to receive(:deliver)
    end

    it 'calls Onetime::Mail.deliver with template and data' do
      worker.perform(message)

      expect(Onetime::Mail).to have_received(:deliver).with(
        :welcome,
        { 'email_address' => 'test@example.com', 'secret' => 'abc123' }
      )
    end

    it 'converts template string to symbol' do
      worker.perform(message)

      expect(Onetime::Mail).to have_received(:deliver).with(:welcome, anything)
    end

    context 'with different templates' do
      it 'handles secret_link template' do
        msg = { 'template' => 'secret_link', 'data' => { 'recipient' => 'user@example.com' } }
        worker.perform(msg)

        expect(Onetime::Mail).to have_received(:deliver).with(:secret_link, anything)
      end

      it 'handles password_request template' do
        msg = { 'template' => 'password_request', 'data' => { 'email_address' => 'user@example.com' } }
        worker.perform(msg)

        expect(Onetime::Mail).to have_received(:deliver).with(:password_request, anything)
      end
    end

    context 'when email delivery fails' do
      before do
        allow(Onetime::Mail).to receive(:deliver)
          .and_raise(StandardError, 'SMTP connection failed')
      end

      it 'raises the error for retry handling' do
        expect { worker.perform(message) }
          .to raise_error(StandardError, 'SMTP connection failed')
      end
    end
  end
end
