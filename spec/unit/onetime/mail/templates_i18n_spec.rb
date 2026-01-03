# spec/unit/onetime/mail/templates_i18n_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Email template i18n integration' do
  # Set up I18n for email template tests
  # This mirrors the setup from try/support/test_helpers.rb and the SetupI18n initializer
  before(:all) do
    # Store original I18n state to restore after tests
    @original_available_locales = I18n.available_locales
    @original_default_locale = I18n.default_locale
    @original_load_path = I18n.load_path.dup

    # Configure I18n for tests - must set available_locales BEFORE default_locale
    I18n.available_locales = [:en]
    I18n.default_locale = :en

    # Add JSON backend support if not already present
    unless I18n::Backend::Simple.include?(Onetime::Initializers::SetupI18n::JsonBackend)
      I18n::Backend::Simple.include(Onetime::Initializers::SetupI18n::JsonBackend)
    end

    # Load email locale files
    locale_files = Dir[File.join(Onetime::HOME, 'src/locales/en/*.json')]
    locale_files.each do |file|
      I18n.load_path << file unless I18n.load_path.include?(file)
    end

    # Force reload of translations
    I18n.backend.reload!
  end

  after(:all) do
    # Restore original I18n state
    I18n.available_locales = @original_available_locales
    I18n.default_locale = @original_default_locale
    I18n.load_path.replace(@original_load_path)
    I18n.backend.reload!
  end

  describe Onetime::Mail::Templates::EmailTranslations do
    describe '.translate' do
      it 'returns translated string for valid key' do
        result = described_class.translate('email.secret_link.subject', sender_email: 'test@example.com')
        expect(result).to eq('test@example.com sent you a secret')
      end

      it 'interpolates variables correctly' do
        result = described_class.translate(
          'email.welcome.subject',
          product_name: 'My Secret App'
        )
        expect(result).to eq('Welcome to My Secret App - Please verify your email')
      end

      it 'uses default locale (en) when not specified' do
        result = described_class.translate('email.common.greeting')
        expect(result).to eq('Hello,')
      end

      it 'accepts locale parameter' do
        result = described_class.translate('email.common.greeting', locale: 'en')
        expect(result).to eq('Hello,')
      end

      it 'returns key path for missing translation' do
        result = described_class.translate('email.nonexistent.key')
        # I18n returns "Translation missing: en.email.nonexistent.key" (capital T)
        expect(result.downcase).to include('translation missing')
      end
    end

    describe '.reset!' do
      it 'is a no-op for backward compatibility' do
        # Should not raise an error
        expect { described_class.reset! }.not_to raise_error
      end
    end
  end

  describe Onetime::Mail::Templates::Base::TemplateContext do
    let(:data) do
      {
        recipient: 'user@example.com',
        sender_email: 'sender@example.com',
        product_name: 'Test Product',
        display_domain: 'secrets.example.com',
        share_domain: 'share.example.com',
        baseuri: 'https://example.com',
      }
    end
    let(:locale) { 'en' }
    let(:context) { described_class.new(data, locale) }

    describe '#t' do
      it 'delegates to EmailTranslations.translate' do
        result = context.t('email.common.greeting')
        expect(result).to eq('Hello,')
      end

      it 'passes interpolation options' do
        result = context.t('email.secret_link.subject', sender_email: 'test@example.com')
        expect(result).to eq('test@example.com sent you a secret')
      end

      it 'uses the context locale' do
        context_fr = described_class.new(data, 'fr')
        # Verify it stores the locale correctly
        expect(context_fr.instance_variable_get(:@locale)).to eq('fr')
      end
    end

    describe '#product_name' do
      context 'when product_name is in data' do
        it 'returns the data value' do
          expect(context.product_name).to eq('Test Product')
        end
      end

      context 'when product_name is not in data' do
        let(:data) { { recipient: 'user@example.com' } }

        it 'returns site_product_name fallback' do
          # Falls back to site config or 'Onetime Secret'
          result = context.product_name
          expect(result).to be_a(String)
          expect(result).not_to be_empty
        end
      end
    end

    describe '#display_domain' do
      context 'when display_domain is in data' do
        it 'returns the data value' do
          expect(context.display_domain).to eq('secrets.example.com')
        end
      end

      context 'when display_domain is not in data but share_domain is' do
        let(:data) { { share_domain: 'share.example.com' } }

        it 'falls back to share_domain' do
          expect(context.display_domain).to eq('share.example.com')
        end
      end

      context 'when neither display_domain nor share_domain is in data' do
        let(:data) { {} }

        it 'falls back to site_host' do
          result = context.display_domain
          # Falls back to site config value (may vary by environment)
          expect(result).to be_a(String)
          expect(result).not_to be_empty
        end
      end
    end

    describe '#baseuri' do
      context 'when baseuri is in data' do
        it 'returns the data value' do
          expect(context.baseuri).to eq('https://example.com')
        end
      end

      context 'when baseuri is not in data' do
        let(:data) { {} }

        it 'falls back to site_baseuri' do
          result = context.baseuri
          # Falls back to site config value (may vary by environment)
          expect(result).to be_a(String)
          expect(result).to match(%r{\Ahttps?://})
        end
      end
    end

    describe '#h' do
      it 'HTML escapes the input' do
        expect(context.h('<script>alert("xss")</script>')).to eq('&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;')
      end

      it 'handles ampersands' do
        expect(context.h('foo & bar')).to eq('foo &amp; bar')
      end
    end

    describe '#u' do
      it 'URL encodes the input' do
        expect(context.u('hello world')).to eq('hello%20world')
      end

      it 'encodes special characters' do
        expect(context.u('foo=bar&baz=qux')).to eq('foo%3Dbar%26baz%3Dqux')
      end
    end

    describe 'method_missing for data access' do
      it 'provides access to data keys as methods' do
        expect(context.recipient).to eq('user@example.com')
        expect(context.sender_email).to eq('sender@example.com')
      end

      it 'raises NoMethodError for unknown keys' do
        expect { context.nonexistent_key }.to raise_error(NoMethodError)
      end
    end

    describe '#respond_to_missing?' do
      it 'returns true for data keys' do
        expect(context.respond_to?(:recipient)).to be true
        expect(context.respond_to?(:sender_email)).to be true
      end

      it 'returns false for unknown keys' do
        expect(context.respond_to?(:nonexistent_key)).to be false
      end
    end
  end

  describe Onetime::Mail::Templates::SecretLink do
    let(:template_data) do
      {
        secret_key: 'abc123xyz',
        recipient: 'recipient@example.com',
        sender_email: 'sender@example.com',
        share_domain: 'secrets.example.com',
      }
    end

    describe '#subject' do
      it 'returns translated subject with interpolated sender email' do
        template = described_class.new(template_data)
        expect(template.subject).to eq('sender@example.com sent you a secret')
      end

      it 'respects locale parameter' do
        template = described_class.new(template_data, locale: 'en')
        expect(template.subject).to include('sent you a secret')
      end
    end

    describe '#render_text' do
      it 'includes translated content from locale file' do
        template = described_class.new(template_data)
        text = template.render_text

        # Check for translated strings
        expect(text).to include('sent you a secret')
        expect(text).to include('This link will only work once')
        expect(text).to include('Onetime Secret')
      end

      it 'includes the secret URL path' do
        template = described_class.new(template_data)
        text = template.render_text

        expect(text).to include('/secret/abc123xyz')
      end

      it 'includes sender email' do
        template = described_class.new(template_data)
        text = template.render_text

        expect(text).to include('sender@example.com')
      end
    end

    describe '#render_html' do
      it 'includes translated content from locale file' do
        template = described_class.new(template_data)
        html = template.render_html

        expect(html).to include('sent you a secret')
        expect(html).to include('Important:')
        expect(html).to include('This link will only work once')
        expect(html).to include('Onetime Secret')
      end

      it 'includes properly escaped content' do
        data_with_special_chars = template_data.merge(
          sender_email: 'test<script>@example.com'
        )
        template = described_class.new(data_with_special_chars)
        html = template.render_html

        # Should be HTML escaped
        expect(html).to include('&lt;script&gt;')
        expect(html).not_to include('<script>')
      end
    end

    describe 'validation' do
      it 'raises ArgumentError when secret_key is missing' do
        data = template_data.except(:secret_key)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Secret key required')
      end

      it 'raises ArgumentError when recipient is missing' do
        data = template_data.except(:recipient)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Recipient required')
      end

      it 'raises ArgumentError when sender_email is missing' do
        data = template_data.except(:sender_email)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Sender email required')
      end
    end
  end

  describe Onetime::Mail::Templates::Welcome do
    let(:mock_secret) do
      double('Secret', identifier: 'verify123token')
    end
    let(:template_data) do
      {
        email_address: 'newuser@example.com',
        secret: mock_secret,
        product_name: 'My Secret App',
      }
    end

    describe '#subject' do
      it 'returns translated subject with interpolated product name' do
        template = described_class.new(template_data)
        expect(template.subject).to eq('Welcome to My Secret App - Please verify your email')
      end

      it 'uses default product name when not provided' do
        data = template_data.except(:product_name)
        template = described_class.new(data)
        # Falls back to site config or 'Onetime Secret'
        expect(template.subject).to include('Welcome to')
        expect(template.subject).to include('Please verify your email')
      end
    end

    describe '#render_text' do
      it 'includes translated content' do
        template = described_class.new(template_data)
        text = template.render_text

        expect(text).to include('verify')
      end
    end

    describe 'validation' do
      it 'raises ArgumentError when email_address is missing' do
        data = template_data.except(:email_address)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Email address required')
      end

      it 'raises ArgumentError when verification_path and secret are both missing' do
        data = template_data.except(:secret)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Verification path or secret required')
      end
    end
  end

  describe Onetime::Mail::Templates::PasswordRequest do
    let(:mock_secret) do
      double('Secret', identifier: 'reset456token')
    end
    let(:template_data) do
      {
        email_address: 'user@example.com',
        secret: mock_secret,
        display_domain: 'secrets.example.com',
        product_name: 'Test Service',
      }
    end

    describe '#subject' do
      it 'returns translated subject with interpolated display_domain' do
        template = described_class.new(template_data)
        expect(template.subject).to eq('Reset your password (secrets.example.com)')
      end

      it 'uses site host when display_domain not provided' do
        data = template_data.except(:display_domain)
        template = described_class.new(data)
        # Falls back to site_host
        expect(template.subject).to match(/Reset your password \(.+\)/)
      end
    end

    describe '#render_text' do
      it 'includes translated content' do
        template = described_class.new(template_data)
        text = template.render_text

        # Template uses "reset your password" phrasing
        expect(text).to include('reset your password')
        expect(text).to include('/forgot/reset456token')
      end
    end

    describe 'validation' do
      it 'raises ArgumentError when email_address is missing' do
        data = template_data.except(:email_address)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Email address required')
      end

      it 'raises ArgumentError when reset_password_path and secret are both missing' do
        data = template_data.except(:secret)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Reset password path or secret required')
      end
    end
  end

  describe Onetime::Mail::Templates::FeedbackEmail do
    let(:template_data) do
      {
        email_address: 'feedback@example.com',
        message: 'This is my feedback message',
        display_domain: 'onetimesecret.com',
        domain_strategy: 'custom',
      }
    end

    describe '#subject' do
      it 'returns translated subject with interpolated values' do
        template = described_class.new(template_data)
        subject = template.subject

        expect(subject).to include('Feedback')
        expect(subject).to include('onetimesecret.com')
        expect(subject).to include('custom')
      end

      it 'uses default strategy when not provided' do
        data = template_data.except(:domain_strategy)
        template = described_class.new(data)

        expect(template.subject).to include('default')
      end
    end

    describe 'validation' do
      it 'raises ArgumentError when email_address is missing' do
        data = template_data.except(:email_address)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Email address required')
      end

      it 'raises ArgumentError when message is missing' do
        data = template_data.except(:message)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Message required')
      end

      it 'raises ArgumentError when display_domain is missing' do
        data = template_data.except(:display_domain)
        expect { described_class.new(data) }.to raise_error(ArgumentError, 'Display domain required')
      end
    end
  end

  describe 'Locale propagation' do
    describe 'default locale behavior' do
      it 'uses en as default locale for Base' do
        # SecretLink.new takes a hash as first positional arg, locale is keyword arg
        template = Onetime::Mail::Templates::SecretLink.new(
          {
            secret_key: 'abc123',
            recipient: 'test@example.com',
            sender_email: 'sender@example.com',
          }
        )
        expect(template.locale).to eq('en')
      end
    end

    describe 'explicit locale setting' do
      it 'respects locale parameter passed to constructor' do
        template = Onetime::Mail::Templates::SecretLink.new(
          { secret_key: 'abc123', recipient: 'test@example.com', sender_email: 'sender@example.com' },
          locale: 'de'
        )
        expect(template.locale).to eq('de')
      end

      it 'propagates locale to TemplateContext' do
        # Add 'fr' to available locales temporarily for this test
        original_locales = I18n.available_locales
        I18n.available_locales = [:en, :fr]

        template = Onetime::Mail::Templates::SecretLink.new(
          { secret_key: 'abc123', recipient: 'test@example.com', sender_email: 'sender@example.com' },
          locale: 'fr'
        )
        # Should not raise even with missing translations (falls back to key)
        expect { template.render_text }.not_to raise_error

        I18n.available_locales = original_locales
      end
    end
  end

  describe 'to_email integration' do
    let(:template_data) do
      {
        secret_key: 'abc123xyz',
        recipient: 'recipient@example.com',
        sender_email: 'sender@example.com',
      }
    end

    it 'builds complete email hash with translated subject' do
      template = Onetime::Mail::Templates::SecretLink.new(template_data)
      email = template.to_email(from: 'noreply@example.com')

      expect(email[:to]).to eq('recipient@example.com')
      expect(email[:from]).to eq('noreply@example.com')
      expect(email[:subject]).to eq('sender@example.com sent you a secret')
      expect(email[:text_body]).to include('sent you a secret')
      expect(email[:html_body]).to include('sent you a secret')
    end

    it 'includes reply_to when provided' do
      template = Onetime::Mail::Templates::SecretLink.new(template_data)
      email = template.to_email(from: 'noreply@example.com', reply_to: 'support@example.com')

      expect(email[:reply_to]).to eq('support@example.com')
    end
  end
end
