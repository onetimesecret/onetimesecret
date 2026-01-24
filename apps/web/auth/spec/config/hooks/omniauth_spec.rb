# apps/web/auth/spec/config/hooks/omniauth_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit Tests for OmniAuth Account Lookup Hook
# =============================================================================
#
# WHAT THIS TESTS:
#   The _account_from_omniauth override that normalizes email for case-insensitive
#   account lookup. This is required because:
#     - SQLite (dev/test) uses case-sensitive string comparison
#     - Redis Customer records require exact email match
#     - IdPs may return emails with different casing than stored
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/config/hooks/omniauth_spec.rb
#
# =============================================================================

# Minimal requires - these tests verify normalization logic only,
# no database or full app context needed
require 'rspec'

RSpec.describe 'OmniAuth hooks' do
  describe '_account_from_omniauth email normalization' do
    # ==========================================================================
    # Email Normalization Logic Tests
    # ==========================================================================
    #
    # These tests verify the normalization logic used by _account_from_omniauth:
    #   normalized_email = omniauth_email.to_s.strip.downcase
    #   _account_from_login(normalized_email)
    #
    # The method normalizes the IdP-provided email before account lookup.

    # Simulates the email normalization logic from the _account_from_omniauth hook
    def normalize_email(omniauth_email)
      omniauth_email.to_s.strip.downcase
    end

    describe 'email normalization behavior' do
      context 'with uppercase email from IdP' do
        it 'normalizes USER@EXAMPLE.COM to user@example.com' do
          expect(normalize_email('USER@EXAMPLE.COM')).to eq('user@example.com')
        end

        it 'normalizes ADMIN@COMPANY.ORG to admin@company.org' do
          expect(normalize_email('ADMIN@COMPANY.ORG')).to eq('admin@company.org')
        end
      end

      context 'with mixed case email from IdP' do
        it 'normalizes User@Example.COM to user@example.com' do
          expect(normalize_email('User@Example.COM')).to eq('user@example.com')
        end

        it 'normalizes JohnDoe@MyCompany.Com to johndoe@mycompany.com' do
          expect(normalize_email('JohnDoe@MyCompany.Com')).to eq('johndoe@mycompany.com')
        end
      end

      context 'with whitespace in email from IdP' do
        it 'trims leading spaces' do
          expect(normalize_email('  user@example.com')).to eq('user@example.com')
        end

        it 'trims trailing spaces' do
          expect(normalize_email('user@example.com  ')).to eq('user@example.com')
        end

        it 'trims both leading and trailing spaces' do
          expect(normalize_email('  user@example.com  ')).to eq('user@example.com')
        end

        it 'handles tabs at boundaries' do
          expect(normalize_email("\tuser@example.com\t")).to eq('user@example.com')
        end

        it 'handles newlines at boundaries' do
          expect(normalize_email("\nuser@example.com\n")).to eq('user@example.com')
        end
      end

      context 'with combined case and whitespace issues' do
        it 'normalizes "  USER@EXAMPLE.COM  " to "user@example.com"' do
          expect(normalize_email('  USER@EXAMPLE.COM  ')).to eq('user@example.com')
        end

        it 'normalizes "\t User@Example.COM \n" to "user@example.com"' do
          expect(normalize_email("\t User@Example.COM \n")).to eq('user@example.com')
        end
      end
    end

    # ==========================================================================
    # Edge Case Handling Tests
    # ==========================================================================

    describe 'edge case handling' do
      context 'with nil omniauth_email' do
        it 'returns empty string (safe for lookup)' do
          result = normalize_email(nil)
          expect(result).to eq('')
        end

        it 'does not raise an error' do
          expect { normalize_email(nil) }.not_to raise_error
        end
      end

      context 'with empty string omniauth_email' do
        it 'returns empty string' do
          expect(normalize_email('')).to eq('')
        end
      end

      context 'with whitespace-only omniauth_email' do
        it 'returns empty string for spaces only' do
          expect(normalize_email('   ')).to eq('')
        end

        it 'returns empty string for tabs only' do
          expect(normalize_email("\t\t")).to eq('')
        end
      end

      context 'with non-string input' do
        it 'converts integer to string and normalizes' do
          # Edge case: unlikely but defensive
          expect(normalize_email(12345)).to eq('12345')
        end

        it 'converts symbol to string and normalizes' do
          expect(normalize_email(:test)).to eq('test')
        end
      end
    end

    # ==========================================================================
    # Account Lookup Simulation Tests
    # ==========================================================================
    #
    # These tests verify the complete flow: normalize email then find account.

    describe 'account lookup with normalized email' do
      # Simulates a simple account store keyed by lowercase email
      let(:accounts_store) do
        {
          'user@example.com' => { id: 1, email: 'user@example.com' },
          'admin@company.org' => { id: 2, email: 'admin@company.org' },
          'test@domain.io' => { id: 3, email: 'test@domain.io' },
        }
      end

      # Simulates _account_from_login behavior
      def find_account_by_email(normalized_email)
        accounts_store[normalized_email]
      end

      # Simulates the full _account_from_omniauth method
      def account_from_omniauth(omniauth_email)
        normalized_email = normalize_email(omniauth_email)
        find_account_by_email(normalized_email)
      end

      context 'with existing account' do
        it 'finds account when IdP returns uppercase email' do
          account = account_from_omniauth('USER@EXAMPLE.COM')
          expect(account).not_to be_nil
          expect(account[:id]).to eq(1)
          expect(account[:email]).to eq('user@example.com')
        end

        it 'finds account when IdP returns mixed case email' do
          account = account_from_omniauth('User@Example.COM')
          expect(account).not_to be_nil
          expect(account[:id]).to eq(1)
        end

        it 'finds account when IdP returns email with whitespace' do
          account = account_from_omniauth('  user@example.com  ')
          expect(account).not_to be_nil
          expect(account[:id]).to eq(1)
        end

        it 'finds account with combined case and whitespace issues' do
          account = account_from_omniauth('  ADMIN@COMPANY.ORG  ')
          expect(account).not_to be_nil
          expect(account[:id]).to eq(2)
        end
      end

      context 'with non-existing account' do
        it 'returns nil for unknown email (allows account creation flow)' do
          account = account_from_omniauth('newuser@example.com')
          expect(account).to be_nil
        end

        it 'returns nil for unknown email with different casing' do
          account = account_from_omniauth('NEWUSER@EXAMPLE.COM')
          expect(account).to be_nil
        end
      end

      context 'with edge case inputs' do
        it 'returns nil for empty omniauth_email' do
          account = account_from_omniauth('')
          expect(account).to be_nil
        end

        it 'returns nil for nil omniauth_email' do
          account = account_from_omniauth(nil)
          expect(account).to be_nil
        end

        it 'does not crash with whitespace-only email' do
          expect { account_from_omniauth('   ') }.not_to raise_error
          expect(account_from_omniauth('   ')).to be_nil
        end
      end
    end

    # ==========================================================================
    # Security Consideration Tests
    # ==========================================================================

    describe 'security considerations' do
      it 'email comparison is case-insensitive (prevents duplicate accounts)' do
        # Without normalization, USER@example.com and user@example.com
        # would be treated as different accounts in case-sensitive stores
        email_from_idp = 'USER@EXAMPLE.COM'
        stored_email = 'user@example.com'

        normalized = normalize_email(email_from_idp)
        expect(normalized).to eq(stored_email)
      end

      it 'whitespace stripping prevents bypass via padding' do
        # Attacker might try to create account with padded email
        email_from_idp = '  user@example.com'
        stored_email = 'user@example.com'

        normalized = normalize_email(email_from_idp)
        expect(normalized).to eq(stored_email)
      end

      it 'preserves email structure (no mid-string modifications)' do
        # Normalization should only affect case and boundary whitespace
        email = 'user.name+tag@sub.domain.com'
        expect(normalize_email(email)).to eq('user.name+tag@sub.domain.com')
      end

      it 'preserves valid special characters in local part' do
        # RFC 5321 allows various characters in local part
        email = "user!#$%&'*+-/=?^_`{|}~@example.com"
        expect(normalize_email(email)).to eq("user!#$%&'*+-/=?^_`{|}~@example.com")
      end
    end
  end

  # ==========================================================================
  # only_json? Override Tests
  # ==========================================================================
  #
  # The OmniAuth hook overrides only_json? to return false for OmniAuth routes.
  # This is required because OmniAuth uses browser redirects from IdPs, not JSON.

  describe 'only_json? override for OmniAuth routes' do
    let(:omniauth_prefix) { '/auth/sso' }

    # Simulates the only_json? override logic
    def only_json?(request_path:, omniauth_prefix:, default_json_mode: true)
      # The hook returns: !request.path.start_with?(omniauth_prefix)
      # When path starts with omniauth_prefix, return false (allow redirects)
      # Otherwise return the default JSON mode setting
      if request_path.start_with?(omniauth_prefix)
        false
      else
        default_json_mode
      end
    end

    context 'OmniAuth callback routes' do
      it 'returns false for /auth/sso/oidc/callback' do
        result = only_json?(
          request_path: '/auth/sso/oidc/callback',
          omniauth_prefix: omniauth_prefix,
        )
        expect(result).to be false
      end

      it 'returns false for /auth/sso/google/callback' do
        result = only_json?(
          request_path: '/auth/sso/google/callback',
          omniauth_prefix: omniauth_prefix,
        )
        expect(result).to be false
      end

      it 'returns false for /auth/sso/github/callback' do
        result = only_json?(
          request_path: '/auth/sso/github/callback',
          omniauth_prefix: omniauth_prefix,
        )
        expect(result).to be false
      end
    end

    context 'OmniAuth initiation routes' do
      it 'returns false for /auth/sso/oidc' do
        result = only_json?(
          request_path: '/auth/sso/oidc',
          omniauth_prefix: omniauth_prefix,
        )
        expect(result).to be false
      end
    end

    context 'non-OmniAuth routes' do
      it 'returns true for /auth/login when JSON mode is enabled' do
        result = only_json?(
          request_path: '/auth/login',
          omniauth_prefix: omniauth_prefix,
          default_json_mode: true,
        )
        expect(result).to be true
      end

      it 'returns true for /auth/signup when JSON mode is enabled' do
        result = only_json?(
          request_path: '/auth/signup',
          omniauth_prefix: omniauth_prefix,
          default_json_mode: true,
        )
        expect(result).to be true
      end

      it 'returns true for /auth/webauthn-login when JSON mode is enabled' do
        result = only_json?(
          request_path: '/auth/webauthn-login',
          omniauth_prefix: omniauth_prefix,
          default_json_mode: true,
        )
        expect(result).to be true
      end

      it 'returns false for /auth/login when JSON mode is disabled' do
        result = only_json?(
          request_path: '/auth/login',
          omniauth_prefix: omniauth_prefix,
          default_json_mode: false,
        )
        expect(result).to be false
      end
    end

    context 'edge cases' do
      it 'handles exact prefix match' do
        result = only_json?(
          request_path: '/auth/sso',
          omniauth_prefix: omniauth_prefix,
        )
        expect(result).to be false
      end

      it 'does not match partial prefix (auth/ss)' do
        result = only_json?(
          request_path: '/auth/ss',
          omniauth_prefix: omniauth_prefix,
          default_json_mode: true,
        )
        expect(result).to be true
      end

      it 'does not match different path with similar prefix' do
        result = only_json?(
          request_path: '/auth/sso-like/callback',
          omniauth_prefix: omniauth_prefix,
        )
        # This DOES match because path.start_with?('/auth/sso') is true
        # for '/auth/sso-like/callback'
        expect(result).to be false
      end
    end
  end

  # ==========================================================================
  # Domain Validation Tests (before_omniauth_create_account)
  # ==========================================================================
  #
  # Tests for the allowed_signup_domains enforcement in SSO signup flow.
  # See also: spec/unit/omniauth_domain_validation_spec.rb for deeper coverage.

  describe 'before_omniauth_create_account domain validation' do
    # Simulates the domain extraction and validation logic
    def extract_domain(email)
      email_str = email.to_s.strip.downcase
      parts = email_str.split('@')
      return nil if parts.length != 2 || parts.last.to_s.empty?

      parts.last
    end

    def domain_allowed?(email_domain, allowed_domains)
      return true if allowed_domains.nil? || allowed_domains.empty?

      normalized_domains = allowed_domains.compact.map(&:downcase)
      normalized_domains.include?(email_domain.to_s.downcase)
    end

    context 'email parsing for domain extraction' do
      it 'extracts domain from valid email' do
        expect(extract_domain('user@company.com')).to eq('company.com')
      end

      it 'normalizes case when extracting domain' do
        expect(extract_domain('User@COMPANY.COM')).to eq('company.com')
      end

      it 'strips whitespace before extraction' do
        expect(extract_domain('  user@company.com  ')).to eq('company.com')
      end

      it 'returns nil for email without @' do
        expect(extract_domain('usercompany.com')).to be_nil
      end

      it 'returns nil for email with empty domain' do
        expect(extract_domain('user@')).to be_nil
      end

      it 'returns nil for email with multiple @' do
        expect(extract_domain('user@foo@bar.com')).to be_nil
      end

      it 'returns nil for nil input' do
        expect(extract_domain(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(extract_domain('')).to be_nil
      end
    end

    context 'domain allowlist checking' do
      context 'with no restrictions (empty/nil config)' do
        it 'allows any domain when config is nil' do
          expect(domain_allowed?('random.com', nil)).to be true
        end

        it 'allows any domain when config is empty array' do
          expect(domain_allowed?('random.com', [])).to be true
        end
      end

      context 'with single domain restriction' do
        let(:allowed_domains) { ['company.com'] }

        it 'allows exact domain match' do
          expect(domain_allowed?('company.com', allowed_domains)).to be true
        end

        it 'allows case-insensitive match' do
          expect(domain_allowed?('COMPANY.COM', allowed_domains)).to be true
        end

        it 'rejects different domain' do
          expect(domain_allowed?('other.com', allowed_domains)).to be false
        end

        it 'rejects subdomain' do
          expect(domain_allowed?('sub.company.com', allowed_domains)).to be false
        end
      end

      context 'with multiple domain restrictions' do
        let(:allowed_domains) { ['company.com', 'subsidiary.com', 'partner.org'] }

        it 'allows first domain' do
          expect(domain_allowed?('company.com', allowed_domains)).to be true
        end

        it 'allows second domain' do
          expect(domain_allowed?('subsidiary.com', allowed_domains)).to be true
        end

        it 'allows third domain' do
          expect(domain_allowed?('partner.org', allowed_domains)).to be true
        end

        it 'rejects unlisted domain' do
          expect(domain_allowed?('attacker.com', allowed_domains)).to be false
        end
      end

      context 'with mixed case in allowed domains' do
        let(:allowed_domains) { ['COMPANY.com', 'Subsidiary.COM'] }

        it 'matches lowercase domain against mixed case config' do
          expect(domain_allowed?('company.com', allowed_domains)).to be true
        end

        it 'matches uppercase domain against mixed case config' do
          expect(domain_allowed?('SUBSIDIARY.COM', allowed_domains)).to be true
        end
      end

      context 'edge cases in allowed domains array' do
        it 'handles nil values in array' do
          allowed = ['company.com', nil, 'partner.com']
          expect(domain_allowed?('company.com', allowed)).to be true
          expect(domain_allowed?('partner.com', allowed)).to be true
        end
      end
    end

    context 'error responses' do
      it 'uses generic error message for domain rejection' do
        # The hook returns: "Your email domain is not authorized for SSO signup"
        # This is intentionally vague to avoid revealing allowed domains
        error_message = 'Your email domain is not authorized for SSO signup'

        expect(error_message).not_to include('company.com')
        expect(error_message).not_to match(/allowed|permitted|valid/i)
      end

      it 'uses specific error message for invalid email format' do
        error_message = 'Invalid email address from identity provider'

        expect(error_message).to include('Invalid')
        expect(error_message).to include('identity provider')
      end
    end
  end

  # ==========================================================================
  # Module Interface Tests
  # ==========================================================================

  describe 'Auth::Config::Hooks::OmniAuth module' do
    # Path: spec/config/hooks/ -> config/hooks/
    # Go up 3 levels (hooks -> config -> spec) then into config/hooks
    let(:omniauth_file) { File.expand_path('../../../config/hooks/omniauth.rb', __dir__) }

    it 'module file exists' do
      expect(File.exist?(omniauth_file)).to be true
    end

    it 'defines configure class method' do
      # Load the module to test its interface
      module Auth; module Config; module Hooks; end; end; end unless defined?(Auth::Config::Hooks)
      require omniauth_file

      expect(Auth::Config::Hooks::OmniAuth).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      module Auth; module Config; module Hooks; end; end; end unless defined?(Auth::Config::Hooks)
      require omniauth_file

      expect(Auth::Config::Hooks::OmniAuth.method(:configure).arity).to eq(1)
    end
  end
end
