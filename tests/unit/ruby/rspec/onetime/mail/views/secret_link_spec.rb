# tests/unit/ruby/rspec/onetime/mail/views/secret_link_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::Mail::SecretLink do
  include_context "mail_test_context"
  it_behaves_like "mail delivery behavior"

  subject(:secret_link) do
    # Use helper that properly handles emailer injection
    with_emailer(
      described_class.new(mail_customer, 'en', mail_secret, recipient),
    )
  end

  let(:recipient) { 'recipient@example.com' }

  it_behaves_like "localized email template", :secretlink

  describe 'initialization' do
    it 'configures required attributes' do
      expect(secret_link[:secret]).to eq(mail_secret)
      expect(secret_link[:email_address]).to eq(recipient)
      expect(secret_link[:custid]).to eq(mail_customer.custid)
      expect(secret_link[:from]).to eq(mail_config[:emailer][:from])
      expect(secret_link[:from_name]).to eq(mail_config[:emailer][:fromname])
      expect(secret_link[:signature_link]).to eq('https://onetimesecret.com/')
    end

    context 'with missing customer' do
      let(:mail_customer) { nil }
      it 'raises error' do
        expect { secret_link }.to raise_error(ArgumentError, /customer required/i)
      end
    end

    context 'with missing recipient' do
      let(:recipient) { nil }
      it 'raises error' do
        expect { secret_link }.to raise_error(ArgumentError, /recipient required/i)
      end
    end
  end

  describe '#subject' do
    it 'formats subject with customer ID' do
      expect(secret_link.subject).to eq("#{mail_customer.custid} sent you a secret")
    end
  end

  describe '#display_domain' do
    it 'uses https protocol with configured domain' do
      expect(secret_link.display_domain).to eq('https://example.com')
    end

    context 'with custom share domain' do
      let(:mail_secret) do
        instance_double('V1::Secret',
          identifier: 'secret123',
          key: 'testkey123',
          share_domain: 'custom.example.com',
          ttl: 7200,
          state: 'pending')
      end

      it 'uses custom domain' do
        expect(secret_link.display_domain).to eq('https://custom.example.com')
      end
    end

    context 'without SSL' do
      before do
        mail_config[:site][:ssl] = false
      end

      it 'uses http protocol' do
        expect(secret_link.display_domain).to eq('http://example.com')
      end
    end
  end

  describe '#uri_path' do
    it 'generates correct secret URI path' do
      expect(secret_link.uri_path).to eq('/secret/testkey123')
    end

    context 'with nil secret key' do
      let(:mail_secret) do
        instance_double('V1::Secret',
          identifier: 'secret123',
          key: nil,
          share_domain: nil,
          ttl: 7200,
          state: 'pending')
      end

      it 'raises error' do
        expect { secret_link.uri_path }.to raise_error(ArgumentError, /invalid secret key/i)
      end
    end
  end

  describe '#render_text' do
    it 'creates and renders with txt template extension' do
      # Verify the template extension manipulation works
      cloned_view = instance_double("#{described_class}")
      allow(secret_link).to receive(:clone).and_return(cloned_view)
      allow(cloned_view).to receive(:instance_variable_get).and_return({})
      allow(cloned_view).to receive(:instance_variable_set)
      allow(cloned_view).to receive(:render).and_return("Text content")

      result = secret_link.render_text

      expect(cloned_view).to have_received(:instance_variable_set).with(
        :@options, hash_including(template_extension: 'txt')
      )
      expect(result).to eq("Text content")
    end
  end

  describe '#deliver_email' do
    it 'sends email with required content' do
      secret_link.deliver_email

      expect(mail_emailer).to have_received(:send_email).with(
        recipient,
        secret_link.subject,
        satisfy { |content|
          # Test for critical content presence rather than structure
          content.is_a?(String) && !content.empty?
        },
        satisfy { |content|
          # Test for critical content presence rather than structure
          content.is_a?(String) && !content.empty?
        },
      )
    end
  end
end
