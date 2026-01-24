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
