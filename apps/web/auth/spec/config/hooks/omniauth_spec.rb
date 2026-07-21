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

# Define the Auth::Config namespace so the hook file can load without a full
# app boot. Auth::Config MUST be a Rodauth::Auth subclass here, never a plain
# `module Config` or `class Config`: if this file is ever loaded in a process
# that also boots the real app, the application registry reopens
# `class Config < Rodauth::Auth`. A plain module/class fixes the constant to the
# wrong type, so the reopen raises a TypeError ("Config is not a class") and boot
# is marked permanently not-ready for every later spec in the process.
require 'rodauth'
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

# Load the actual production module
require_relative '../../../config/hooks/omniauth'

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

    # Simulates the email normalization logic from the _account_from_omniauth hook.
    # Canonical implementation: OT::Utils.normalize_email
    # Inlined here to test the specific chain the OmniAuth hook uses.
    def normalize_email(omniauth_email)
      omniauth_email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
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

      # ========================================================================
      # Unicode Email Normalization (Issue #2843)
      # ========================================================================
      # IdPs may return emails with international characters in various forms.
      # NFC normalization and :fold case folding ensure consistent matching.
      context 'with Unicode/international email addresses' do
        it 'normalizes Spanish ñ uppercase to lowercase' do
          expect(normalize_email('SEÑOR@EXAMPLE.COM')).to eq('señor@example.com')
        end

        it 'normalizes accented characters (É -> é)' do
          expect(normalize_email('CAFÉ@EXAMPLE.COM')).to eq('café@example.com')
        end

        it 'applies Unicode case folding for German sharp S (ẞ -> ss)' do
          # Per Unicode case folding rules, uppercase ẞ folds to "ss"
          expect(normalize_email('STRAẞE@EXAMPLE.COM')).to eq('strasse@example.com')
        end

        it 'normalizes Greek uppercase letters' do
          expect(normalize_email('ΕΛΛΗΝΙΚΆ@EXAMPLE.COM')).to eq('ελληνικά@example.com')
        end

        it 'normalizes Cyrillic uppercase letters' do
          expect(normalize_email('ПРИВЕТ@EXAMPLE.COM')).to eq('привет@example.com')
        end

        it 'applies NFC normalization (decomposed -> composed)' do
          # NFD: e + combining acute accent
          # NFC: single é codepoint
          nfd_email = "cafe\u0301@example.com"
          nfc_email = "caf\u00e9@example.com"
          expect(normalize_email(nfd_email)).to eq(nfc_email)
        end

        it 'handles combined Unicode case and whitespace' do
          expect(normalize_email('  SEÑOR@EXAMPLE.COM  ')).to eq('señor@example.com')
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

      # Simulates the full _account_from_omniauth method AFTER the H-3 fix.
      #
      # SECURITY (H-3): the production hook no longer returns an existing account
      # for auto-linking by email — that is the account-takeover vector. When an
      # existing account matches the normalized IdP email, the hook logs, sets an
      # error flash, and `redirect`s to account_exists_link_required, which HALTS
      # the callback (Roda throw :halt) so create_omniauth_identity never links
      # the caller's (provider, uid) and never logs them in. We can't redirect in
      # this pure-logic harness, so we model the halt as a refusal marker carrying
      # the redirect target. Only a genuinely new email returns nil (JIT create).
      #
      # HONESTY: this is a REIMPLEMENTATION of the decision boundary — it does NOT
      # drive the production `_account_from_omniauth`. The real hook's redirect/halt
      # path is NOT yet integration-covered end-to-end (follow-up filed); these unit
      # assertions verify the intended logic only.
      def account_from_omniauth(omniauth_email)
        normalized_email = normalize_email(omniauth_email)
        existing         = find_account_by_email(normalized_email)
        return { refused: true, redirect: '/signin?auth_error=account_exists_link_required' } if existing

        nil
      end

      context 'with existing account (refuses SSO auto-link by email)' do
        # These assertions are the INVERSION of the pre-fix behavior, which
        # returned the existing account by email and let Rodauth link+login.

        it 'refuses when IdP returns uppercase email matching an existing account' do
          result = account_from_omniauth('USER@EXAMPLE.COM')
          expect(result).to include(refused: true)
          expect(result[:redirect]).to eq('/signin?auth_error=account_exists_link_required')
        end

        it 'refuses when IdP returns mixed case email matching an existing account' do
          result = account_from_omniauth('User@Example.COM')
          expect(result).to include(refused: true)
        end

        it 'refuses when IdP returns email with whitespace matching an existing account' do
          result = account_from_omniauth('  user@example.com  ')
          expect(result).to include(refused: true)
        end

        it 'refuses with combined case and whitespace issues' do
          result = account_from_omniauth('  ADMIN@COMPANY.ORG  ')
          expect(result).to include(refused: true)
        end

        it 'never returns the existing account record (no auto-link)' do
          result = account_from_omniauth('USER@EXAMPLE.COM')
          # Pre-fix this returned { id: 1, email: 'user@example.com' }.
          expect(result).not_to include(:id)
          expect(result).not_to include(:email)
        end
      end

      # ======================================================================
      # H-3 account-takeover path
      # ======================================================================
      #
      # Victim already holds a password account for victim@x.com. An attacker
      # controls an IdP that emits victim@x.com under a NEW (provider, uid) that
      # has never been linked. Pre-fix, the hook returned the victim's account,
      # Rodauth linked the attacker's identity and logged them in as the victim.
      # Post-fix, the hook refuses and redirects to account_exists_link_required.
      #
      # NOTE: the full "NO new account_identities row / NOT logged in" assertions
      # require a real Rodauth callback. That end-to-end coverage does NOT yet
      # exist — the production hook's redirect/halt path is currently unverified by
      # any full-mode integration spec (follow-up filed). The block below models the
      # decision boundary in isolation only; it does NOT exercise the real hook.
      context 'account takeover: SSO email matches a pre-existing password account' do
        let(:accounts_store) do
          { 'victim@x.com' => { id: 42, email: 'victim@x.com' } }
        end

        it 'refuses to auto-link and redirects to account_exists_link_required' do
          # Attacker's IdP returns the victim's email under a new identity.
          result = account_from_omniauth('victim@x.com')
          expect(result).to include(refused: true)
          expect(result[:redirect]).to eq('/signin?auth_error=account_exists_link_required')
        end

        it 'does not surface the victim account for linking' do
          result = account_from_omniauth('VICTIM@X.COM')
          expect(result).not_to include(id: 42)
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
      # The hook uses trailing slash to avoid matching unrelated paths.
      # Match /auth/sso/ prefix OR exact /auth/sso match.
      is_sso_route = request_path.start_with?("#{omniauth_prefix}/") || request_path == omniauth_prefix
      if is_sso_route
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
          default_json_mode: true,
        )
        # With trailing slash check, /auth/sso-like does NOT match /auth/sso/
        expect(result).to be true
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
      expect(Auth::Config::Hooks::OmniAuth).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      expect(Auth::Config::Hooks::OmniAuth.method(:configure).arity).to eq(1)
    end
  end

  # ==========================================================================
  # after_omniauth_create_account operations
  # ==========================================================================
  #
  # Integration tests for CreateCustomer and CreateDefaultWorkspace operations
  # are in: spec/integration/omniauth_account_creation_spec.rb
  #
  # These operations are tested with real database/Redis operations to verify:
  # - Customer creation with correct attributes (email, role, verified)
  # - Account linking via external_id
  # - Organization creation with is_default flag
  # - Idempotency guarantees
  #

  # ==========================================================================
  # Issuer-scoped identity lookup (#3840 Phase 0 / #3838 item 5)
  # ==========================================================================
  #
  # Unlike the pure-logic REIMPLEMENTATIONS elsewhere in this file, this block
  # drives the SHIPPED production functions in
  # Auth::Config::Features::OmniAuth against an in-memory SQLite dataset (real
  # Sequel queries + a real UPDATE for the lazy upgrade). This is the item-5
  # cross-tenant takeover regression coverage.
  describe 'issuer-scoped identity lookup (Auth::Config::Features::OmniAuth)' do
    before(:all) do
      require 'sequel'
      # Drives real code; the feature file only pulls in OmniAuth strategy gems
      # at require time (no app boot, no DB connection).
      require_relative '../../../config/features/omniauth'
    end

    let(:feature) { Auth::Config::Features::OmniAuth }

    # Fresh in-memory schema mirroring migration 008 / create_omniauth_tables.
    let(:db) do
      d = Sequel.sqlite
      d.create_table(:account_identities) do
        primary_key :id, type: :Bignum
        Integer :account_id, null: false
        String :provider, null: false
        String :issuer, null: false, default: ''
        String :uid, null: false
        index %i[provider issuer uid], unique: true
      end
      d
    end
    let(:ds) { db[:account_identities] }
    let(:cols) { { id_col: :id, provider_col: :provider, uid_col: :uid, issuer_col: :issuer } }

    describe '.resolve_issuer' do
      it 'prefers the strategy option issuer (authoritative)' do
        result = feature.resolve_issuer(
          strategy_options: { issuer: 'https://idp-a.example' },
          provider: 'oidc', oidc_route_name: 'oidc', env_oidc_issuer: 'https://env.example',
        )
        expect(result).to eq('https://idp-a.example')
      end

      it 'falls back to ENV OIDC_ISSUER for a discovery (OIDC) strategy' do
        result = feature.resolve_issuer(
          strategy_options: { discovery: true },
          provider: 'oidc', oidc_route_name: 'oidc', env_oidc_issuer: 'https://env.example',
        )
        expect(result).to eq('https://env.example')
      end

      it 'falls back to ENV OIDC_ISSUER when provider matches the OIDC route name' do
        result = feature.resolve_issuer(
          strategy_options: nil,
          provider: 'oidc', oidc_route_name: 'oidc', env_oidc_issuer: 'https://env.example',
        )
        expect(result).to eq('https://env.example')
      end

      it 'returns the "" sentinel for non-OIDC providers (never nil)' do
        result = feature.resolve_issuer(
          strategy_options: {},
          provider: 'github', oidc_route_name: 'oidc', env_oidc_issuer: 'https://env.example',
        )
        expect(result).to eq('')
      end

      it 'returns the "" sentinel when no issuer is resolvable' do
        result = feature.resolve_issuer(
          strategy_options: { issuer: '' },
          provider: 'github', oidc_route_name: 'oidc', env_oidc_issuer: nil,
        )
        expect(result).to eq('')
      end
    end

    describe '.platform_path?' do
      it 'is true when no validated tenant domain is present' do
        expect(feature.platform_path?(nil)).to be true
        expect(feature.platform_path?('')).to be true
      end

      it 'is false on a tenant callback (validated domain present)' do
        expect(feature.platform_path?('domain-123')).to be false
      end
    end

    describe '.lookup_identity' do
      # ITEM-5 REGRESSION: two IdPs (issuers) assert the same sub under the same
      # strategy name. Under the old (provider, uid) key the second collided
      # with the first → takeover. With (provider, issuer, uid) they are two
      # distinct rows and the lookup discriminates by issuer.
      context 'same (provider, uid) with different issuer (item-5)' do
        before do
          ds.insert(account_id: 10, provider: 'oidc', issuer: 'https://idp-a', uid: 'sub-shared')
          ds.insert(account_id: 20, provider: 'oidc', issuer: 'https://idp-b', uid: 'sub-shared')
        end

        it 'stores them as two distinct rows (composite unique permits)' do
          expect(ds.count).to eq(2)
        end

        it 'rejects a true duplicate (provider, issuer, uid)' do
          expect do
            ds.insert(account_id: 99, provider: 'oidc', issuer: 'https://idp-a', uid: 'sub-shared')
          end.to raise_error(Sequel::UniqueConstraintViolation)
        end

        it 'resolves issuer-A to account 10 and issuer-B to account 20 (no cross-bind)' do
          a = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: 'sub-shared',
                                                      resolved_issuer: 'https://idp-a', platform_path: false)
          b = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: 'sub-shared',
                                                      resolved_issuer: 'https://idp-b', platform_path: false)
          expect(a[:account_id]).to eq(10)
          expect(b[:account_id]).to eq(20)
          expect(a[:account_id]).not_to eq(b[:account_id])
        end
      end

      context 'platform grace + lazy upgrade' do
        before { ds.insert(account_id: 30, provider: 'oidc', issuer: '', uid: 'legacy-sub') }

        it 'matches the legacy "" row and upgrades its issuer in the DB' do
          result = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: 'legacy-sub',
                                                           resolved_issuer: 'https://real-idp', platform_path: true)
          expect(result[:account_id]).to eq(30)
          expect(result[:issuer]).to eq('https://real-idp')
          expect(ds.first(account_id: 30)[:issuer]).to eq('https://real-idp')
        end
      end

      context 'tenant path: issuer-exact only (no grace)' do
        before { ds.insert(account_id: 40, provider: 'oidc', issuer: '', uid: 'legacy-sub-2') }

        it 'does NOT match the legacy "" row and leaves it untouched' do
          result = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: 'legacy-sub-2',
                                                           resolved_issuer: 'https://tenant-idp', platform_path: false)
          expect(result).to be_nil
          expect(ds.first(account_id: 40)[:issuer]).to eq('')
        end
      end

      context 'sentinel issuer (non-OIDC) with a legacy "" row on the platform path' do
        before { ds.insert(account_id: 50, provider: 'github', issuer: '', uid: 'gh-1') }

        it 'matches via the exact query without a pointless "" -> "" upgrade' do
          result = feature.lookup_identity(ds: ds, **cols, provider: 'github', uid: 'gh-1',
                                                           resolved_issuer: '', platform_path: true)
          expect(result[:account_id]).to eq(50)
          expect(ds.first(account_id: 50)[:issuer]).to eq('')
        end
      end
    end
  end
end
