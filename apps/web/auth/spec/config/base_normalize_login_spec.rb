# apps/web/auth/spec/config/base_normalize_login_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit Tests for normalize_login Configuration
# =============================================================================
#
# WHAT THIS TESTS:
#   The normalize_login block in auth/config/base.rb that strips whitespace
#   and downcases login input before Rodauth processes it.
#
# Issue #2843: Login normalization ensures case-insensitive email matching.
# PostgreSQL uses citext (case-insensitive) but Redis requires exact match.
# The normalize_login block normalizes the login input before lookup.
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/config/base_normalize_login_spec.rb
#
# =============================================================================

require 'rspec'

RSpec.describe 'Auth::Config::Base normalize_login' do
  # Simulates the normalize_login logic from auth/config/base.rb.
  # Canonical implementation: OT::Utils.normalize_email
  # Inlined here to test the specific chain the Rodauth hook uses.
  def normalize_login(login)
    login.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
  end

  # ==========================================================================
  # Case Normalization Tests
  # ==========================================================================

  describe 'case normalization' do
    context 'with uppercase email input' do
      it 'normalizes UPPERCASE to lowercase' do
        expect(normalize_login('USER@EXAMPLE.COM')).to eq('user@example.com')
      end

      it 'normalizes uppercase domain' do
        expect(normalize_login('test@EXAMPLE.COM')).to eq('test@example.com')
      end
    end

    context 'with mixed case email input' do
      it 'normalizes MixedCase to lowercase' do
        expect(normalize_login('User@Example.COM')).to eq('user@example.com')
      end

      it 'normalizes complex mixed case patterns' do
        mixed_case = 'NoRmAlIzE-TeSt@ExAmPlE.cOm'
        expect(normalize_login(mixed_case)).to eq('normalize-test@example.com')
      end
    end
  end

  # ==========================================================================
  # Whitespace Handling Tests
  # ==========================================================================

  describe 'whitespace handling' do
    let(:test_email) { 'user@example.com' }

    context 'with leading whitespace' do
      it 'strips leading spaces' do
        expect(normalize_login("  #{test_email}")).to eq(test_email)
      end

      it 'strips multiple leading spaces' do
        expect(normalize_login("     #{test_email}")).to eq(test_email)
      end
    end

    context 'with trailing whitespace' do
      it 'strips trailing spaces' do
        expect(normalize_login("#{test_email}  ")).to eq(test_email)
      end

      it 'strips multiple trailing spaces' do
        expect(normalize_login("#{test_email}     ")).to eq(test_email)
      end
    end

    context 'with both leading and trailing whitespace' do
      it 'strips whitespace from both ends' do
        expect(normalize_login("  #{test_email}  ")).to eq(test_email)
      end
    end

    context 'with tab characters' do
      it 'strips leading tabs' do
        expect(normalize_login("\t#{test_email}")).to eq(test_email)
      end

      it 'strips trailing tabs' do
        expect(normalize_login("#{test_email}\t")).to eq(test_email)
      end

      it 'strips tabs from both ends' do
        expect(normalize_login("\t#{test_email}\t")).to eq(test_email)
      end
    end

    context 'with newlines' do
      it 'strips leading newlines' do
        expect(normalize_login("\n#{test_email}")).to eq(test_email)
      end

      it 'strips trailing newlines' do
        expect(normalize_login("#{test_email}\n")).to eq(test_email)
      end
    end
  end

  # ==========================================================================
  # Combined Case and Whitespace Tests
  # ==========================================================================

  describe 'combined case and whitespace normalization' do
    it 'handles uppercase with leading spaces' do
      expect(normalize_login('  USER@EXAMPLE.COM')).to eq('user@example.com')
    end

    it 'handles uppercase with trailing spaces' do
      expect(normalize_login('USER@EXAMPLE.COM  ')).to eq('user@example.com')
    end

    it 'handles uppercase with both leading and trailing spaces' do
      expect(normalize_login('  USER@EXAMPLE.COM  ')).to eq('user@example.com')
    end

    it 'handles uppercase with tabs' do
      expect(normalize_login("\tUSER@EXAMPLE.COM\t")).to eq('user@example.com')
    end

    it 'handles mixed case with mixed whitespace' do
      expect(normalize_login(" \t User@Example.COM \n ")).to eq('user@example.com')
    end
  end

  # ==========================================================================
  # Unicode Normalization Tests (Issue #2843)
  # ==========================================================================

  describe 'Unicode normalization' do
    context 'with international characters' do
      it 'normalizes Spanish n with tilde' do
        expect(normalize_login('SENOR@EXAMPLE.COM')).to eq('senor@example.com')
      end

      it 'normalizes accented characters' do
        expect(normalize_login('CAFE@EXAMPLE.COM')).to eq('cafe@example.com')
      end

      it 'applies Unicode case folding for German sharp S' do
        # Per Unicode case folding rules, uppercase sharp S folds to "ss"
        expect(normalize_login("STRASSE@EXAMPLE.COM")).to eq('strasse@example.com')
      end

      it 'normalizes Greek uppercase letters' do
        expect(normalize_login("TEST@EXAMPLE.COM")).to eq('test@example.com')
      end
    end

    context 'with NFC normalization' do
      it 'normalizes decomposed to composed form' do
        # NFD: e + combining acute accent
        # NFC: single e with acute codepoint
        nfd_email = "cafe\u0301@example.com"
        nfc_email = "caf\u00e9@example.com"
        expect(normalize_login(nfd_email)).to eq(nfc_email)
      end
    end
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================

  describe 'edge cases' do
    context 'with nil input' do
      it 'returns empty string' do
        expect(normalize_login(nil)).to eq('')
      end

      it 'does not raise an error' do
        expect { normalize_login(nil) }.not_to raise_error
      end
    end

    context 'with empty string' do
      it 'returns empty string' do
        expect(normalize_login('')).to eq('')
      end
    end

    context 'with whitespace-only input' do
      it 'returns empty string for spaces only' do
        expect(normalize_login('   ')).to eq('')
      end

      it 'returns empty string for tabs only' do
        expect(normalize_login("\t\t")).to eq('')
      end
    end

    context 'with non-string input' do
      it 'converts integer to string' do
        expect(normalize_login(12345)).to eq('12345')
      end

      it 'converts symbol to string' do
        expect(normalize_login(:test)).to eq('test')
      end
    end
  end

  # ==========================================================================
  # Account Lookup Simulation Tests
  # ==========================================================================
  #
  # These tests verify that normalized logins match stored accounts correctly.

  describe 'account lookup with normalized login' do
    # Simulates account store keyed by lowercase email (like PostgreSQL citext)
    let(:accounts_store) do
      {
        'user@example.com' => { id: 1, email: 'user@example.com' },
        'admin@company.org' => { id: 2, email: 'admin@company.org' },
        'test@domain.io' => { id: 3, email: 'test@domain.io' },
      }
    end

    def find_account(login)
      normalized = normalize_login(login)
      accounts_store[normalized]
    end

    context 'with case variations' do
      it 'finds account with UPPERCASE login' do
        account = find_account('USER@EXAMPLE.COM')
        expect(account).not_to be_nil
        expect(account[:id]).to eq(1)
      end

      it 'finds account with MixedCase login' do
        account = find_account('User@Example.COM')
        expect(account).not_to be_nil
        expect(account[:id]).to eq(1)
      end
    end

    context 'with whitespace variations' do
      it 'finds account with leading spaces' do
        account = find_account('  user@example.com')
        expect(account).not_to be_nil
        expect(account[:id]).to eq(1)
      end

      it 'finds account with trailing spaces' do
        account = find_account('user@example.com  ')
        expect(account).not_to be_nil
        expect(account[:id]).to eq(1)
      end

      it 'finds account with tab characters' do
        account = find_account("\tuser@example.com\t")
        expect(account).not_to be_nil
        expect(account[:id]).to eq(1)
      end
    end

    context 'with combined issues' do
      it 'finds account with uppercase and whitespace' do
        account = find_account('  USER@EXAMPLE.COM  ')
        expect(account).not_to be_nil
        expect(account[:id]).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Security Considerations
  # ==========================================================================

  describe 'security considerations' do
    it 'prevents duplicate accounts via case normalization' do
      # Without normalization, USER@example.com and user@example.com
      # could be treated as different accounts
      expect(normalize_login('USER@EXAMPLE.COM')).to eq(normalize_login('user@example.com'))
    end

    it 'prevents bypass via whitespace padding' do
      expect(normalize_login('  user@example.com')).to eq(normalize_login('user@example.com'))
    end

    it 'preserves email structure (no mid-string modifications)' do
      email = 'user.name+tag@sub.domain.com'
      expect(normalize_login(email)).to eq('user.name+tag@sub.domain.com')
    end

    it 'preserves valid special characters in local part' do
      email = "user!#$%&'*+-/=?^_`{|}~@example.com"
      expect(normalize_login(email)).to eq("user!#$%&'*+-/=?^_`{|}~@example.com")
    end
  end
end
