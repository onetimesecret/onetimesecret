# tests/unit/ruby/rspec/onetime/app/mail/secret_link_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::App::Mail::SecretLink do
  include_context "mail_test_context"
  it_behaves_like "mail delivery behavior"


  subject(:secret_link) do
    # Use helper that properly handles emailer injection
    with_emailer(
      described_class.new(mail_customer, 'en', mail_secret, recipient)
    )
  end

  it_behaves_like "localized email template", :secretlink



  let(:init_args) { [mail_secret, 'recipient@example.com'] }
  let(:locale) { 'en' }
  let(:recipient) { 'recipient@example.com' }
  let(:expected_content) do
    {
      secret: mail_secret,
      email_address: 'recipient@example.com',
      custid: mail_customer.custid,
      from: mail_config[:emailer][:from],
      from_name: mail_config[:emailer][:fromname],
      signature_link: 'https://onetimesecret.com/'
    }
  end

  describe 'initialization order' do
    it 'sets up emailer before calling init' do
      initialization_order = []

      # Track order of operations
      allow(mail_emailer).to receive(:fromname=) do |name|
        initialization_order << [:set_fromname, name]
      end

      secret_link

      expect(initialization_order).to eq([
        [:set_fromname, 'Onetime Secret']
      ])
    end
  end

  describe 'email sender name' do
    it 'sends emails with correct from name' do
      secret_link.deliver_email

      expect(mail_emailer).to have_received(:send_email).with(
        recipient,
        anything,
        include('Onetime Secret') # Verify name appears in content
      )
    end
  end

  it_behaves_like "mustache template behavior", "secret_link", check_filesystem: true do
    let(:expected_content) do
      {
        secret: mail_secret,
        email_address: recipient,
        custid: mail_customer.custid,
        from: mail_config[:emailer][:from],
        from_name: mail_config[:emailer][:fromname],
        signature_link: 'https://onetimesecret.com/',
        display_domain: 'https://example.com',
        uri_path: '/secret/testkey123'
      }
    end
  end

  describe 'initialization' do
    it 'configures required attributes' do
      expect(secret_link[:secret]).to eq(mail_secret)
      expect(secret_link[:email_address]).to eq(recipient)
      expect(secret_link[:custid]).to eq(mail_customer.custid)
      expect(secret_link[:from]).to eq(mail_config[:emailer][:from])
      expect(secret_link[:from_name]).to eq(mail_config[:emailer][:fromname])
      expect(secret_link[:signature_link]).to eq('https://onetimesecret.com/')
    end

    it 'sets emailer from name after initialization' do
      secret_link # Force initialization
      expect(mail_emailer).to have_received(:fromname=).with('Onetime Secret')
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
    context 'with valid locale data' do
      it 'formats subject with customer ID' do
        expect(secret_link.subject).to eq("#{mail_customer.custid} sent you a secret")
      end
    end

    context 'with missing locale data' do
      let(:locale) { 'xx' }
      it 'falls back to English' do
        expect(secret_link.subject).to eq("#{mail_customer.custid} sent you a secret")
      end
    end
  end

  describe '#display_domain' do
    context 'with default configuration' do
      it 'uses https protocol with configured domain' do
        expect(secret_link.display_domain).to eq('https://example.com')
      end
    end

    context 'with custom share domain' do
      let(:mail_secret) do
        instance_double('Secret',
          identifier: 'secret123',
          key: 'testkey123',
          share_domain: 'custom.example.com',
          ttl: 7200,
          state: 'pending'
        )
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
        instance_double('Secret',
          identifier: 'secret123',
          key: nil,
          share_domain: nil,
          ttl: 7200,
          state: 'pending'
        )
      end

      it 'raises error' do
        expect { secret_link.uri_path }.to raise_error(ArgumentError, /invalid secret key/i)
      end
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
          content.include?(secret_link.display_domain) &&
          content.include?(secret_link.uri_path) &&
          content.include?(mail_customer.custid) &&
          content.include?('<!DOCTYPE html') # Verify it's HTML
        }
      )
    end
  end

  describe '#render and delivery' do
    let(:rendered_content) { secret_link.render }

    it 'renders email with required content' do
      expect(rendered_content).to include(secret_link.display_domain)
      expect(rendered_content).to include(secret_link.uri_path)
      expect(rendered_content).to include(mail_customer.custid)
      expect(rendered_content).to include('<!DOCTYPE html')
    end

    it 'delivers email with rendered content' do
      secret_link.deliver_email

      expect(mail_emailer).to have_received(:send_email).with(
        recipient,
        secret_link.subject,
        rendered_content
      )
    end
  end



end
