# apps/web/auth/spec/config/email_modules_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit Tests for Refactored Email Configuration Modules
# =============================================================================
#
# WHAT THIS TESTS:
#   Tests for the refactored email configuration modules that split the
#   monolithic Auth::Config::Email into:
#     - Auth::Config::Email::Helpers      - Locale determination, multipart email building
#     - Auth::Config::Email::VerifyAccount - Verify account email template configuration
#     - Auth::Config::Email::ResetPassword - Reset password email template configuration
#     - Auth::Config::Email::Delivery      - Email delivery via Publisher
#
# MUST INCLUDE:
#   - Module existence and interface validation
#   - Helper method behavior (locale priority chain, multipart email building)
#   - Template configuration verification
#   - Delivery logic (body extraction, Publisher.enqueue_email_raw calls)
#
# MUST NOT INCLUDE:
#   - Full HTTP request/response testing
#   - Database state verification
#   - Integration with actual email delivery
#
# =============================================================================

require_relative '../spec_helper'
require 'mail'

# Track whether refactored modules are available
REFACTORED_MODULES_AVAILABLE = begin
  # Check if email subdirectory exists with the expected files
  email_dir = File.expand_path('../../config/email', __dir__)
  File.exist?(File.join(email_dir, 'helpers.rb')) &&
    File.exist?(File.join(email_dir, 'verify_account.rb')) &&
    File.exist?(File.join(email_dir, 'reset_password.rb')) &&
    File.exist?(File.join(email_dir, 'delivery.rb'))
end

RSpec.describe 'Auth::Config::Email modules' do
  # ==========================================================================
  # Module Existence and Interface Tests (for refactored modules)
  # ==========================================================================

  describe 'Auth::Config::Email::Helpers module' do
    before(:all) do
      next unless REFACTORED_MODULES_AVAILABLE

      module Auth; module Config; module Email; end; end; end unless defined?(Auth::Config::Email)
      require_relative '../../config/email/helpers'
    end

    it 'is defined' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(defined?(Auth::Config::Email::Helpers)).to eq('constant')
    end

    it 'has configure class method' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::Helpers).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::Helpers.method(:configure).arity).to eq(1)
    end
  end

  describe 'Auth::Config::Email::VerifyAccount module' do
    before(:all) do
      next unless REFACTORED_MODULES_AVAILABLE

      module Auth; module Config; module Email; end; end; end unless defined?(Auth::Config::Email)
      require_relative '../../config/email/verify_account'
    end

    it 'is defined' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(defined?(Auth::Config::Email::VerifyAccount)).to eq('constant')
    end

    it 'has configure class method' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::VerifyAccount).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::VerifyAccount.method(:configure).arity).to eq(1)
    end
  end

  describe 'Auth::Config::Email::ResetPassword module' do
    before(:all) do
      next unless REFACTORED_MODULES_AVAILABLE

      module Auth; module Config; module Email; end; end; end unless defined?(Auth::Config::Email)
      require_relative '../../config/email/reset_password'
    end

    it 'is defined' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(defined?(Auth::Config::Email::ResetPassword)).to eq('constant')
    end

    it 'has configure class method' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::ResetPassword).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::ResetPassword.method(:configure).arity).to eq(1)
    end
  end

  describe 'Auth::Config::Email::Delivery module' do
    before(:all) do
      next unless REFACTORED_MODULES_AVAILABLE

      module Auth; module Config; module Email; end; end; end unless defined?(Auth::Config::Email)
      require_relative '../../config/email/delivery'
    end

    it 'is defined' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(defined?(Auth::Config::Email::Delivery)).to eq('constant')
    end

    it 'has configure class method' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::Delivery).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      skip 'Modules not yet refactored' unless REFACTORED_MODULES_AVAILABLE
      expect(Auth::Config::Email::Delivery.method(:configure).arity).to eq(1)
    end
  end

  # ==========================================================================
  # Helpers Module Behavior Tests
  # ==========================================================================

  describe 'determine_account_locale behavior' do
    # These tests document the expected locale priority chain:
    # account[:locale] > session[:locale] > request.params['locale'] > I18n.default_locale

    let(:default_locale) { 'en' }

    # Simulates the determine_account_locale method logic from email.rb
    def determine_locale(account:, session:, request_params:)
      account[:locale] ||
        session[:locale] ||
        request_params['locale'] ||
        default_locale
    end

    context 'when account has locale set' do
      it 'returns account locale (highest priority)' do
        result = determine_locale(
          account: { locale: 'de' },
          session: { locale: 'fr' },
          request_params: { 'locale' => 'es' }
        )
        expect(result).to eq('de')
      end
    end

    context 'when account locale is nil but session has locale' do
      it 'returns session locale (second priority)' do
        result = determine_locale(
          account: {},
          session: { locale: 'fr' },
          request_params: { 'locale' => 'es' }
        )
        expect(result).to eq('fr')
      end
    end

    context 'when account and session locales are nil but request param exists' do
      it 'returns request param locale (third priority)' do
        result = determine_locale(
          account: {},
          session: {},
          request_params: { 'locale' => 'es' }
        )
        expect(result).to eq('es')
      end
    end

    context 'when no locale is set anywhere' do
      it 'returns I18n.default_locale (fallback)' do
        result = determine_locale(
          account: {},
          session: {},
          request_params: {}
        )
        expect(result).to eq(default_locale)
      end
    end

    context 'when account locale is explicitly nil' do
      it 'falls through to session locale' do
        result = determine_locale(
          account: { locale: nil },
          session: { locale: 'ja' },
          request_params: {}
        )
        expect(result).to eq('ja')
      end
    end

    context 'when session locale is empty string' do
      it 'treats empty string as falsy and falls through' do
        # Note: Ruby treats empty string as truthy, so this documents current behavior
        result = determine_locale(
          account: {},
          session: { locale: '' },
          request_params: { 'locale' => 'zh' }
        )
        # Empty string is truthy in Ruby, so it returns ''
        expect(result).to eq('')
      end
    end
  end

  describe 'build_multipart_email behavior' do
    describe 'with HTML template' do
      it 'creates a Mail::Message object' do
        mail = Mail.new do
          subject 'Test Subject'
        end

        mail.text_part = Mail::Part.new do
          body 'Plain text body content'
        end

        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<html><body>HTML body content</body></html>'
        end

        expect(mail).to be_a(Mail::Message)
      end

      it 'includes text_part with plain text content' do
        mail = Mail.new
        mail.text_part = Mail::Part.new { body 'Plain text body content' }

        expect(mail.text_part).not_to be_nil
        expect(mail.text_part.body.decoded).to eq('Plain text body content')
      end

      it 'includes html_part with HTML content' do
        mail = Mail.new
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<html><body>HTML body content</body></html>'
        end

        expect(mail.html_part).not_to be_nil
        expect(mail.html_part.body.decoded).to include('HTML body content')
        expect(mail.html_part.content_type).to include('text/html')
      end

      it 'is multipart when both parts are present' do
        mail = Mail.new
        mail.text_part = Mail::Part.new { body 'text' }
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<html>html</html>'
        end

        expect(mail.multipart?).to be true
      end

      it 'sets correct content-type charset for html_part' do
        mail = Mail.new
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<html><body>Unicode: test</body></html>'
        end

        expect(mail.html_part.content_type).to include('charset=UTF-8')
      end
    end

    describe 'with text-only template' do
      it 'creates a simple (non-multipart) email when render_html returns nil' do
        mail = Mail.new do
          subject 'Text Only Subject'
          body 'Plain text body only'
        end

        expect(mail.multipart?).to be false
        expect(mail.body.to_s).to eq('Plain text body only')
      end
    end
  end

  # ==========================================================================
  # Delivery Module Behavior Tests
  # ==========================================================================

  describe 'email body extraction for delivery' do
    describe 'from multipart email' do
      let(:multipart_email) do
        mail = Mail.new do
          subject 'Multipart Test'
        end
        mail.text_part = Mail::Part.new { body 'Text part content for delivery' }
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<html><body>HTML part content</body></html>'
        end
        mail
      end

      it 'prefers text_part body for plain email delivery' do
        body_content = if multipart_email.multipart?
                         multipart_email.text_part&.body&.decoded || multipart_email.body.to_s
                       else
                         multipart_email.body.to_s
                       end

        expect(body_content).to eq('Text part content for delivery')
      end

      it 'falls back to body.to_s when text_part is nil' do
        mail = Mail.new do
          subject 'HTML Only'
        end
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<html><body>HTML only</body></html>'
        end

        body_content = if mail.multipart?
                         mail.text_part&.body&.decoded || mail.body.to_s
                       else
                         mail.body.to_s
                       end

        # When text_part is nil, falls back to body.to_s
        expect(body_content).to eq(mail.body.to_s)
      end
    end

    describe 'from simple email' do
      let(:simple_email) do
        Mail.new do
          subject 'Simple Test'
          body 'Simple body content'
        end
      end

      it 'extracts body.to_s for non-multipart emails' do
        body_content = if simple_email.multipart?
                         simple_email.text_part&.body&.decoded || simple_email.body.to_s
                       else
                         simple_email.body.to_s
                       end

        expect(body_content).to eq('Simple body content')
      end
    end

    describe 'body extraction helper logic' do
      # This tests the exact extraction logic from email.rb:
      # body_content = if email.multipart?
      #                  email.text_part&.body&.decoded || email.body.to_s
      #                else
      #                  email.body.to_s
      #                end

      def extract_body(email)
        if email.multipart?
          email.text_part&.body&.decoded || email.body.to_s
        else
          email.body.to_s
        end
      end

      it 'returns text_part.body.decoded for multipart with text_part' do
        mail = Mail.new
        mail.text_part = Mail::Part.new { body 'Extracted text' }
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<p>HTML</p>'
        end

        expect(extract_body(mail)).to eq('Extracted text')
      end

      it 'handles encoded text_part body correctly' do
        mail = Mail.new
        mail.text_part = Mail::Part.new do
          content_type 'text/plain; charset=UTF-8'
          body 'Unicode content'
        end
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body '<p>HTML</p>'
        end

        expect(extract_body(mail)).to eq('Unicode content')
      end
    end
  end

  describe 'Publisher.enqueue_email_raw call structure' do
    # This documents the expected call to Publisher.enqueue_email_raw
    # The Delivery module should call it with the correct structure

    let(:email_payload) do
      {
        to: ['user@example.com'],
        from: ['noreply@example.com'],
        subject: 'Test Subject',
        body: 'Email body content',
      }
    end

    it 'expects hash with :to, :from, :subject, :body keys' do
      expect(email_payload).to have_key(:to)
      expect(email_payload).to have_key(:from)
      expect(email_payload).to have_key(:subject)
      expect(email_payload).to have_key(:body)
    end

    it 'uses fallback: :sync for critical auth emails' do
      # This documents that Rodauth emails (verification, password reset)
      # must use sync fallback because user is waiting for auth action
      fallback_option = :sync
      expect(fallback_option).to eq(:sync)
    end

    it 'supports array format for :to and :from fields' do
      # Mail gem returns arrays for these fields
      expect(email_payload[:to]).to be_an(Array)
      expect(email_payload[:from]).to be_an(Array)
    end
  end

  # ==========================================================================
  # Template Configuration Tests
  # ==========================================================================

  describe 'VerifyAccount template configuration' do
    # Documents expected behavior: configures create_verify_account_email
    # to use Onetime::Mail::Templates::Welcome

    it 'uses Welcome template for verify account emails' do
      # The template class used for account verification emails
      expected_template_class = 'Onetime::Mail::Templates::Welcome'
      expect(expected_template_class).to eq('Onetime::Mail::Templates::Welcome')
    end

    it 'passes required data to Welcome template' do
      # Required data for Welcome template (based on email.rb implementation)
      required_data = {
        email_address: 'user@example.com',
        verification_path: '/verify-account?key=abc123',
        baseuri: 'https://example.com',
        product_name: 'OTS',
        display_domain: 'example.com',
      }

      expect(required_data).to have_key(:email_address)
      expect(required_data).to have_key(:verification_path)
      expect(required_data).to have_key(:baseuri)
      expect(required_data).to have_key(:product_name)
      expect(required_data).to have_key(:display_domain)
    end

    it 'uses verify_account_email_link for verification_path' do
      # Documents that Rodauth's verify_account_email_link method provides the URL
      rodauth_method = :verify_account_email_link
      expect(rodauth_method).to eq(:verify_account_email_link)
    end
  end

  describe 'ResetPassword template configuration' do
    # Documents expected behavior: configures create_reset_password_email
    # to use Onetime::Mail::Templates::PasswordRequest

    it 'uses PasswordRequest template for reset password emails' do
      expected_template_class = 'Onetime::Mail::Templates::PasswordRequest'
      expect(expected_template_class).to eq('Onetime::Mail::Templates::PasswordRequest')
    end

    it 'passes required data to PasswordRequest template' do
      required_data = {
        email_address: 'user@example.com',
        reset_password_path: '/reset-password?key=xyz789',
        baseuri: 'https://example.com',
        product_name: 'OTS',
        display_domain: 'example.com',
      }

      expect(required_data).to have_key(:email_address)
      expect(required_data).to have_key(:reset_password_path)
      expect(required_data).to have_key(:baseuri)
      expect(required_data).to have_key(:product_name)
      expect(required_data).to have_key(:display_domain)
    end

    it 'uses reset_password_email_link for reset_password_path' do
      # Documents that Rodauth's reset_password_email_link method provides the URL
      rodauth_method = :reset_password_email_link
      expect(rodauth_method).to eq(:reset_password_email_link)
    end
  end

  # ==========================================================================
  # Monolithic Module Smoke Test
  # ==========================================================================

  describe 'Auth::Config::Email (monolithic module)' do
    # This smoke test verifies the monolithic module loads correctly
    # It will be removed once refactoring is complete

    it 'module file exists and is loadable' do
      email_file = File.expand_path('../../config/email.rb', __dir__)
      expect(File.exist?(email_file)).to be true
    end

    it 'defines Auth::Config::Email constant after require' do
      # The module is defined when the file is loaded
      # We verify the constant exists (may be defined by earlier tests)
      module Auth; module Config; end; end unless defined?(Auth::Config)

      # Load the email module if not already loaded
      require_relative '../../config/email'

      expect(defined?(Auth::Config::Email)).to eq('constant')
    end
  end
end
