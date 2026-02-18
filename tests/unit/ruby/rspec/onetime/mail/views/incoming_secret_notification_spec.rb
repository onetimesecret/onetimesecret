# tests/unit/ruby/rspec/onetime/mail/views/incoming_secret_notification_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::Mail::IncomingSecretNotification do
  include_context "mail_test_context"
  it_behaves_like "mail delivery behavior"

  subject(:notification) do
    with_emailer(
      described_class.new(mail_customer, 'en', mail_secret, recipient),
    )
  end

  let(:recipient) { 'recipient@example.com' }

  let(:mail_metadata) do
    instance_double('V2::Metadata',
      memo: 'Test memo',
      has_passphrase?: false)
  end

  before do
    allow(mail_secret).to receive(:metadata_key).and_return('metadata_key_123')
    allow(V2::Metadata).to receive(:load).with('metadata_key_123').and_return(mail_metadata)
  end

  describe 'initialization' do
    it 'configures required attributes' do
      expect(notification[:secret]).to eq(mail_secret)
      expect(notification[:email_address]).to eq(recipient)
      expect(notification[:from]).to eq(mail_config[:emailer][:from])
      expect(notification[:from_name]).to eq(mail_config[:emailer][:fromname])
      expect(notification[:signature_link]).to eq('https://example.com')
    end

    it 'loads memo from metadata' do
      expect(notification[:memo]).to eq('Test memo')
    end

    it 'sets has_passphrase from metadata' do
      expect(notification[:has_passphrase]).to eq(false)
    end

    context 'with passphrase configured' do
      let(:mail_metadata) do
        instance_double('V2::Metadata',
          memo: 'Test memo',
          has_passphrase?: true)
      end

      it 'sets has_passphrase to true' do
        expect(notification[:has_passphrase]).to eq(true)
      end
    end

    context 'with missing secret' do
      let(:mail_secret) { nil }
      it 'raises error' do
        expect { notification }.to raise_error(ArgumentError, /secret required/i)
      end
    end

    context 'with missing recipient' do
      let(:recipient) { nil }
      it 'raises error' do
        expect { notification }.to raise_error(ArgumentError, /recipient required/i)
      end
    end

    context 'with nil metadata' do
      before do
        allow(V2::Metadata).to receive(:load).and_return(nil)
      end

      it 'sets memo to nil' do
        expect(notification[:memo]).to be_nil
      end

      it 'sets has_passphrase to nil' do
        expect(notification[:has_passphrase]).to be_nil
      end
    end
  end

  describe '#subject' do
    it 'returns generic subject without memo' do
      expect(notification.subject).to eq("You've received a secret message")
    end

    it 'does not include memo in subject for security' do
      expect(notification.subject).not_to include('Test memo')
    end
  end

  describe '#display_domain' do
    it 'uses https protocol with configured domain' do
      expect(notification.display_domain).to eq('https://example.com')
    end
  end

  describe '#uri_path' do
    it 'generates correct secret URI path' do
      expect(notification.uri_path).to eq('/secret/testkey123')
    end

    context 'with nil secret key' do
      let(:mail_secret) do
        instance_double('V1::Secret',
          identifier: 'secret123',
          key: nil,
          metadata_key: 'metadata_key_123',
          share_domain: nil,
          ttl: 7200,
          state: 'pending')
      end

      it 'raises error' do
        expect { notification.uri_path }.to raise_error(ArgumentError, /invalid secret key/i)
      end
    end
  end

  describe '#deliver_email' do
    it 'sends email with required content' do
      notification.deliver_email

      expect(mail_emailer).to have_received(:send_email).with(
        recipient,
        notification.subject,
        satisfy { |content| content.is_a?(String) && !content.empty? },
        satisfy { |content| content.is_a?(String) && !content.empty? },
      )
    end
  end

  describe 'template class identity' do
    it 'is distinct from SecretLink' do
      expect(described_class).not_to eq(Onetime::Mail::SecretLink)
    end

    it 'inherits from Mail::Views::Base' do
      expect(described_class.ancestors).to include(Onetime::Mail::Views::Base)
    end

    it 'accepts the same init signature as SecretLink (secret, recipient)' do
      expect(described_class.instance_method(:init).arity).to eq(2)
    end
  end
end
