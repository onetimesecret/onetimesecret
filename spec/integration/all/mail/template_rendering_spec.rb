# spec/integration/all/mail/template_rendering_spec.rb
#
# frozen_string_literal: true

# Integration tests for email template rendering with i18n.
#
# These tests verify that email templates:
# 1. Render without errors (both text and HTML)
# 2. Contain expected translated content (no raw translation keys)
# 3. Properly interpolate variables
# 4. Generate complete email hashes via to_email
#
# Run with: pnpm run test:rspec spec/integration/all/mail/template_rendering_spec.rb

require 'spec_helper'
require 'onetime/mail/templates/base'
require 'onetime/mail/templates/secret_link'
require 'onetime/mail/templates/welcome'
require 'onetime/mail/templates/password_request'
require 'onetime/mail/templates/incoming_secret'
require 'onetime/mail/templates/secret_revealed'
require 'onetime/mail/templates/expiration_warning'
require 'onetime/mail/templates/feedback_email'

RSpec.describe 'Email Template Rendering', type: :integration do
  # Load locale files for i18n translations
  # This mimics the SetupI18n initializer behavior
  before(:all) do
    # Add JSON backend support
    I18n::Backend::Simple.include(Onetime::Initializers::SetupI18n::JsonBackend) unless I18n::Backend::Simple.include?(Onetime::Initializers::SetupI18n::JsonBackend)

    # Configure I18n
    I18n.available_locales = [:en]
    I18n.default_locale = :en

    # Clear and reload locale files
    I18n.load_path.clear
    locale_files = Dir[File.join(ENV['ONETIME_HOME'] || Onetime::HOME, 'src/locales/*/*.json')]
    locale_files.each { |file| I18n.load_path << file }
    I18n.backend.reload!
  end

  # Common test data
  let(:test_email) { 'recipient@example.com' }
  let(:sender_email) { 'sender@example.com' }
  let(:secret_key) { 'abc123xyz' }
  let(:from_address) { 'noreply@onetimesecret.com' }

  # Helper to check for raw translation keys in rendered output
  def contains_raw_translation_key?(text)
    # Match patterns like:
    # - "email.xxx.key" (raw key)
    # - "Translation missing:" (I18n fallback message)
    text.match?(/\bemail\.[a-z_]+\.[a-z_]+\b/i) ||
      text.include?('Translation missing:')
  end

  describe Onetime::Mail::Templates::SecretLink do
    let(:data) do
      {
        secret_key: secret_key,
        recipient: test_email,
        sender_email: sender_email,
        share_domain: nil
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'returns non-empty content' do
        expect(template.render_text).to be_a(String)
        expect(template.render_text).not_to be_empty
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('sent you a secret')
        expect(text).to include('link will only work once')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'interpolates sender_email in content' do
        expect(template.render_text).to include(sender_email)
      end

      it 'interpolates secret_key in URI' do
        expect(template.render_text).to include("/secret/#{secret_key}")
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'returns non-empty content' do
        expect(template.render_html).to be_a(String)
        expect(template.render_html).not_to be_empty
      end

      it 'contains HTML structure' do
        html = template.render_html
        expect(html).to include('<!DOCTYPE')
        expect(html).to include('<html')
        expect(html).to include('</html>')
      end

      it 'contains expected translated phrases' do
        html = template.render_html
        expect(html).to include('sent you a secret')
        expect(html).to include('link will only work once')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject with interpolated sender_email' do
        expect(template.subject).to include(sender_email)
        expect(template.subject).to include('sent you a secret')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has non-nil string values for all fields' do
        expect(email_hash[:to]).to eq(test_email)
        expect(email_hash[:from]).to eq(from_address)
        expect(email_hash[:subject]).to be_a(String)
        expect(email_hash[:text_body]).to be_a(String)
        expect(email_hash[:html_body]).to be_a(String)
      end
    end
  end

  describe Onetime::Mail::Templates::Welcome do
    let(:mock_secret) do
      double('Secret', identifier: 'verify123')
    end
    let(:data) do
      {
        email_address: test_email,
        secret: mock_secret,
        product_name: 'Test Product'
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('Welcome to')
        expect(text).to include('verify')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'interpolates email_address' do
        expect(template.render_text).to include(test_email)
      end

      it 'interpolates product_name' do
        expect(template.render_text).to include('Test Product')
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject with product_name' do
        expect(template.subject).to include('Welcome')
        expect(template.subject).to include('Test Product')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has correct recipient' do
        expect(email_hash[:to]).to eq(test_email)
      end
    end
  end

  describe Onetime::Mail::Templates::PasswordRequest do
    let(:mock_secret) do
      double('Secret', key: 'reset456')
    end
    let(:data) do
      {
        email_address: test_email,
        secret: mock_secret,
        display_domain: 'example.com',
        product_name: 'Test App'
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('reset your password')
        expect(text).to include('ignore this email')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'interpolates email_address' do
        expect(template.render_text).to include(test_email)
      end

      it 'interpolates product_name' do
        expect(template.render_text).to include('Test App')
      end

      it 'includes forgot path with secret key' do
        expect(template.render_text).to include('/forgot/reset456')
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject with display_domain' do
        expect(template.subject).to include('Reset')
        expect(template.subject).to include('password')
        expect(template.subject).to include('example.com')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has correct recipient' do
        expect(email_hash[:to]).to eq(test_email)
      end
    end
  end

  describe Onetime::Mail::Templates::IncomingSecret do
    let(:mock_secret) do
      double('Secret', key: 'incoming789', share_domain: nil)
    end
    let(:data) do
      {
        secret: mock_secret,
        recipient: test_email,
        memo: 'Important document'
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('received a')
        expect(text).to include('secret')
        expect(text).to include('link will only work once')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'includes memo when provided' do
        expect(template.render_text).to include('Important document')
      end

      it 'includes secret path' do
        expect(template.render_text).to include('/secret/incoming789')
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject' do
        expect(template.subject).to include('received a secret')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has correct recipient' do
        expect(email_hash[:to]).to eq(test_email)
      end
    end

    context 'without memo' do
      let(:data) do
        {
          secret: mock_secret,
          recipient: test_email,
          memo: nil
        }
      end

      it 'renders without error when memo is nil' do
        expect { template.render_text }.not_to raise_error
        expect { template.render_html }.not_to raise_error
      end
    end
  end

  describe Onetime::Mail::Templates::SecretRevealed do
    let(:data) do
      {
        recipient: test_email,
        secret_shortid: 'short123',
        revealed_at: Time.now.utc.iso8601
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('was viewed')
        expect(text).to include('automated notification')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'includes secret shortid' do
        expect(template.render_text).to include('short123')
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject' do
        expect(template.subject).to include('was viewed')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has correct recipient' do
        expect(email_hash[:to]).to eq(test_email)
      end
    end
  end

  describe Onetime::Mail::Templates::ExpirationWarning do
    let(:data) do
      {
        recipient: test_email,
        secret_key: secret_key,
        expires_at: Time.now.to_i + 3600, # 1 hour from now
        share_domain: nil
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('expire')
        expect(text).to include('permanently deleted')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'interpolates time_remaining' do
        text = template.render_text
        expect(text).to match(/\d+\s+(hour|minute|day)/)
      end

      it 'includes secret URI' do
        expect(template.render_text).to include("/secret/#{secret_key}")
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject about expiration' do
        expect(template.subject).to include('expire')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has correct recipient' do
        expect(email_hash[:to]).to eq(test_email)
      end
    end
  end

  describe Onetime::Mail::Templates::FeedbackEmail do
    let(:data) do
      {
        email_address: test_email,
        message: 'Great service! Thanks for building this.',
        display_domain: 'custom.example.com',
        domain_strategy: 'custom'
      }
    end
    let(:template) { described_class.new(data) }

    describe '#render_text' do
      it 'renders without error' do
        expect { template.render_text }.not_to raise_error
      end

      it 'contains expected translated phrases' do
        text = template.render_text
        expect(text).to include('Feedback')
        expect(text).to include('From:')
        expect(text).to include('Message:')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_text)).to be false
      end

      it 'includes the feedback message' do
        expect(template.render_text).to include('Great service!')
      end

      it 'includes the email address' do
        expect(template.render_text).to include(test_email)
      end

      it 'includes the display domain' do
        expect(template.render_text).to include('custom.example.com')
      end

      it 'includes the domain strategy' do
        expect(template.render_text).to include('custom')
      end
    end

    describe '#render_html' do
      it 'renders without error' do
        expect { template.render_html }.not_to raise_error
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.render_html)).to be false
      end
    end

    describe '#subject' do
      it 'returns translated subject with domain and strategy' do
        subject = template.subject
        expect(subject).to include('Feedback')
        expect(subject).to include('custom.example.com')
        expect(subject).to include('custom')
      end

      it 'contains no raw translation keys' do
        expect(contains_raw_translation_key?(template.subject)).to be false
      end
    end

    describe '#to_email' do
      let(:email_hash) { template.to_email(from: from_address) }

      it 'returns a hash with all required keys' do
        expect(email_hash).to include(:to, :from, :subject, :text_body, :html_body)
      end

      it 'has correct recipient (sender of feedback)' do
        expect(email_hash[:to]).to eq(test_email)
      end
    end
  end

  describe 'Template validation' do
    # Note: Template classes take a hash as the first positional argument
    it 'SecretLink requires secret_key' do
      expect { Onetime::Mail::Templates::SecretLink.new({ recipient: 'a@b.com', sender_email: 's@b.com' }) }
        .to raise_error(ArgumentError, /Secret key required/)
    end

    it 'SecretLink requires recipient' do
      expect { Onetime::Mail::Templates::SecretLink.new({ secret_key: 'abc', sender_email: 's@b.com' }) }
        .to raise_error(ArgumentError, /Recipient required/)
    end

    it 'SecretLink requires sender_email' do
      expect { Onetime::Mail::Templates::SecretLink.new({ secret_key: 'abc', recipient: 'a@b.com' }) }
        .to raise_error(ArgumentError, /Sender email required/)
    end

    it 'Welcome requires email_address' do
      expect { Onetime::Mail::Templates::Welcome.new({ secret: double('s', identifier: 'x') }) }
        .to raise_error(ArgumentError, /Email address required/)
    end

    it 'Welcome requires secret' do
      expect { Onetime::Mail::Templates::Welcome.new({ email_address: 'a@b.com' }) }
        .to raise_error(ArgumentError, /Secret required/)
    end

    it 'PasswordRequest requires email_address' do
      expect { Onetime::Mail::Templates::PasswordRequest.new({ secret: double('s', key: 'x') }) }
        .to raise_error(ArgumentError, /Email address required/)
    end

    it 'PasswordRequest requires secret' do
      expect { Onetime::Mail::Templates::PasswordRequest.new({ email_address: 'a@b.com' }) }
        .to raise_error(ArgumentError, /Secret required/)
    end

    it 'IncomingSecret requires secret' do
      expect { Onetime::Mail::Templates::IncomingSecret.new({ recipient: 'a@b.com' }) }
        .to raise_error(ArgumentError, /Secret required/)
    end

    it 'IncomingSecret requires recipient' do
      expect { Onetime::Mail::Templates::IncomingSecret.new({ secret: double('s', key: 'x') }) }
        .to raise_error(ArgumentError, /Recipient required/)
    end

    it 'SecretRevealed requires recipient' do
      expect { Onetime::Mail::Templates::SecretRevealed.new({ secret_shortid: 'abc' }) }
        .to raise_error(ArgumentError, /Recipient email required/)
    end

    it 'SecretRevealed requires secret_shortid' do
      expect { Onetime::Mail::Templates::SecretRevealed.new({ recipient: 'a@b.com' }) }
        .to raise_error(ArgumentError, /Secret shortid required/)
    end

    it 'ExpirationWarning requires recipient' do
      expect { Onetime::Mail::Templates::ExpirationWarning.new({ secret_key: 'abc', expires_at: Time.now.to_i }) }
        .to raise_error(ArgumentError, /Recipient required/)
    end

    it 'ExpirationWarning requires secret_key' do
      expect { Onetime::Mail::Templates::ExpirationWarning.new({ recipient: 'a@b.com', expires_at: Time.now.to_i }) }
        .to raise_error(ArgumentError, /Secret key required/)
    end

    it 'ExpirationWarning requires expires_at' do
      expect { Onetime::Mail::Templates::ExpirationWarning.new({ recipient: 'a@b.com', secret_key: 'abc' }) }
        .to raise_error(ArgumentError, /Expiration time required/)
    end

    it 'FeedbackEmail requires email_address' do
      expect { Onetime::Mail::Templates::FeedbackEmail.new({ message: 'x', display_domain: 'd.com' }) }
        .to raise_error(ArgumentError, /Email address required/)
    end

    it 'FeedbackEmail requires message' do
      expect { Onetime::Mail::Templates::FeedbackEmail.new({ email_address: 'a@b.com', display_domain: 'd.com' }) }
        .to raise_error(ArgumentError, /Message required/)
    end

    it 'FeedbackEmail requires display_domain' do
      expect { Onetime::Mail::Templates::FeedbackEmail.new({ email_address: 'a@b.com', message: 'x' }) }
        .to raise_error(ArgumentError, /Display domain required/)
    end
  end

  describe 'Custom domain handling' do
    it 'SecretLink uses share_domain when provided' do
      template = Onetime::Mail::Templates::SecretLink.new({
        secret_key: 'abc',
        recipient: 'a@b.com',
        sender_email: 's@b.com',
        share_domain: 'custom.example.com'
      })
      expect(template.display_domain).to include('custom.example.com')
      expect(template.render_text).to include('custom.example.com')
    end

    it 'ExpirationWarning uses share_domain when provided' do
      template = Onetime::Mail::Templates::ExpirationWarning.new({
        recipient: 'a@b.com',
        secret_key: 'abc',
        expires_at: Time.now.to_i + 3600,
        share_domain: 'custom.example.com'
      })
      expect(template.display_domain).to include('custom.example.com')
      expect(template.render_text).to include('custom.example.com')
    end
  end

  describe 'Locale support' do
    it 'templates default to en locale' do
      template = Onetime::Mail::Templates::SecretLink.new({
        secret_key: 'abc',
        recipient: 'a@b.com',
        sender_email: 's@b.com'
      })
      expect(template.locale).to eq('en')
    end

    it 'templates accept custom locale' do
      template = Onetime::Mail::Templates::SecretLink.new(
        { secret_key: 'abc', recipient: 'a@b.com', sender_email: 's@b.com' },
        locale: 'es'
      )
      expect(template.locale).to eq('es')
    end
  end
end
