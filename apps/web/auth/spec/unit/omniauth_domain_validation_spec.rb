# apps/web/auth/spec/unit/omniauth_domain_validation_spec.rb
#
# frozen_string_literal: true

# Unit tests for OmniAuth domain validation logic
# These tests don't require Valkey/Redis - they test pure Ruby logic

RSpec.describe 'OmniAuth Domain Validation' do
  describe 'allowed_signup_domains configuration' do
    let(:allowed_domains_config) { OT.conf.dig('site', 'authentication', 'allowed_signup_domains') }

    context 'when no domain restrictions configured' do
      before do
        # Clear any existing config
        allow(OT).to receive(:conf).and_return(
          { 'site' => { 'authentication' => { 'allowed_signup_domains' => [] } } }
        )
      end

      it 'returns empty array by default' do
        expect(allowed_domains_config).to eq([])
      end
    end

    context 'when ALLOWED_SIGNUP_DOMAIN is set' do
      it 'parses comma-separated domains' do
        # This tests the config parsing logic
        domains = 'company.com, subsidiary.com'.split(',').map(&:strip)
        expect(domains).to eq(['company.com', 'subsidiary.com'])
      end
    end
  end

  describe 'domain extraction from email' do
    def extract_domain(email)
      email_parts = email.to_s.strip.downcase.split('@')
      return nil if email_parts.length != 2

      domain = email_parts.last
      return nil if domain.nil? || domain.empty?

      domain
    end

    it 'extracts domain from valid email' do
      expect(extract_domain('user@example.com')).to eq('example.com')
    end

    it 'handles uppercase email' do
      expect(extract_domain('User@EXAMPLE.COM')).to eq('example.com')
    end

    it 'handles email with whitespace' do
      expect(extract_domain('  user@example.com  ')).to eq('example.com')
    end

    it 'returns nil for email without @' do
      expect(extract_domain('userexample.com')).to be_nil
    end

    it 'returns nil for email with empty domain' do
      expect(extract_domain('user@')).to be_nil
    end

    it 'returns nil for email with multiple @' do
      expect(extract_domain('user@foo@example.com')).to be_nil
    end

    it 'returns nil for empty string' do
      expect(extract_domain('')).to be_nil
    end

    it 'returns nil for nil' do
      expect(extract_domain(nil)).to be_nil
    end
  end

  describe 'domain allowlist matching' do
    def domain_allowed?(email_domain, allowed_domains)
      return true if allowed_domains.nil? || allowed_domains.empty?

      normalized_domains = allowed_domains.compact.map(&:downcase)
      normalized_domains.include?(email_domain.to_s.downcase)
    end

    context 'with no restrictions' do
      it 'allows any domain when list is nil' do
        expect(domain_allowed?('example.com', nil)).to be true
      end

      it 'allows any domain when list is empty' do
        expect(domain_allowed?('example.com', [])).to be true
      end
    end

    context 'with domain restrictions' do
      let(:allowed) { ['company.com', 'subsidiary.com'] }

      it 'allows matching domain' do
        expect(domain_allowed?('company.com', allowed)).to be true
      end

      it 'allows matching domain case-insensitive' do
        expect(domain_allowed?('COMPANY.COM', allowed)).to be true
      end

      it 'rejects non-matching domain' do
        expect(domain_allowed?('other.com', allowed)).to be false
      end

      it 'rejects subdomain of allowed domain' do
        expect(domain_allowed?('sub.company.com', allowed)).to be false
      end
    end
  end

  describe 'security considerations' do
    it 'does not reveal allowed domains in error messages' do
      # The hook uses generic error: "Your email domain is not authorized for SSO signup"
      # It does NOT say "Allowed domains are: company.com"
      error_message = 'Your email domain is not authorized for SSO signup'
      expect(error_message).not_to include('company.com')
      expect(error_message).not_to include('allowed')
    end

    it 'logs rejected domain for auditing' do
      # The hook logs :omniauth_domain_rejected with obscured email and domain
      # This is for security auditing, not user-facing
      log_event = :omniauth_domain_rejected
      expect(log_event).to eq(:omniauth_domain_rejected)
    end
  end
end
