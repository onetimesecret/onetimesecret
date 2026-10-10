# frozen_string_literal: true

# Regression for #3478. Run with full-sqlite or full-pg-agnostic, both of
# which explicitly enable org SSO and register the OIDC and Entra routes.
require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'OmniAuth Missing Email (issue #3478)', type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  before do
    enable_platform_fallback
    configure_allowed_domains(nil)
  end

  after { teardown_mock_auth }

  def setup_entra_mock_auth(email:, provider: :oidc, uid: nil, raw_info: {})
    enable_omniauth_test_mode
    oid = uid || "oid-#{SecureRandom.uuid}"
    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new(
      provider: provider.to_s,
      uid: oid,
      info: { email: email, name: 'No Mailbox User' },
      credentials: { token: 'mock_access_token', expires: false },
      extra: {
        raw_info: {
          sub: oid,
          oid: oid,
          tid: 'fabrikam-tenant-id',
          preferred_username: 'no.mailbox@fabrikam.onmicrosoft.com',
        }.merge(raw_info),
      },
    )
  end

  def post_sso_callback(provider = :oidc)
    clear_body_headers
    post "/auth/sso/#{provider}/callback"
    expect(last_response.status).not_to eq(404),
      "SSO route #{provider} must be registered; use full-sqlite or full-pg-agnostic"
  end

  # Provisioning boundary only: an HTTP redirect and SQL persistence do not
  # establish successful application-session synchronization (#4726).
  def expect_provisioned_account(email:, uid:, provider: 'oidc')
    expect(last_response.status).to eq(302), last_response.body
    expect(last_response.location.to_s).not_to include('auth_error=')
    account = auth_db[:accounts].where(email: email).first
    expect(account).not_to be_nil
    # citext comparisons ignore case on PostgreSQL; compare the stored value too.
    expect(account[:email]).to eq(email)
    expect(auth_db[:account_identities].where(provider: provider, uid: uid).all)
      .to contain_exactly(hash_including(account_id: account[:id]))
    account
  end

  # Application-session boundary: the SQL account, its one Customer (reached
  # by both the extid link and the case-folded email index), and the session
  # SyncSession populates from that Customer.
  def expect_created_account(email:, uid:, provider: 'oidc')
    account  = expect_provisioned_account(email: email, uid: uid, provider: provider)
    customer = Onetime::Customer.find_by_email(email)
    expect(customer).not_to be_nil
    expect(account[:external_id]).to eq(customer.extid)
    expect(last_request.env['rack.session'].to_h)
      .to include(
        'authenticated' => true,
        'account_id' => account[:id],
        'external_id' => customer.extid,
        'email' => email,
      )
    account
  end

  describe 'when the IdP returns no usable email' do
    [
      ['absent (nil)', nil],
      ['empty string', ''],
      ['spaces only', '   '],
      ['tabs and newlines', "\t\n"],
      ['non-breaking space', "\u00a0"],
    ].each do |label, value|
      it "redirects to missing_email for #{label}" do
        setup_entra_mock_auth(email: value)
        accounts_before = auth_db[:accounts].count
        post_sso_callback
        expect_auth_error_redirect('missing_email')
        expect(auth_db[:accounts].count).to eq(accounts_before)
      end
    end

    it 'handles an omitted email key without raising or creating an account' do
      setup_mock_auth(email: nil)
      expect { post_sso_callback }.not_to change { auth_db[:accounts].count }
      expect_auth_error_redirect('missing_email')
    end
  end

  describe 'structurally malformed emails from the IdP' do
    [
      ['missing @', 'nomailbox.fabrikam.onmicrosoft.com'],
      ['empty local part', '@fabrikam.onmicrosoft.com'],
      ['empty domain', 'nomailbox@'],
      ['bare @', '@'],
      ['multiple @', 'no@mailbox@fabrikam.onmicrosoft.com'],
      ['internal spaces', 'no mailbox@fabrikam.onmicrosoft.com'],
      ['dotless domain', 'nomailbox@fabrikam'],
      ['comma', 'no,mailbox@fabrikam.onmicrosoft.com'],
      ['semicolon', 'nomailbox@fabrikam;onmicrosoft.com'],
      ['comma in domain', 'nomailbox@fabrikam,onmicrosoft.com'],
      ['semicolon in local part', 'no;mailbox@fabrikam.onmicrosoft.com'],
      ['space in domain', 'nomailbox@fabrikam.onmicrosoft com'],
      ['internal newline in local part', "no\nmailbox@fabrikam.onmicrosoft.com"],
      ['internal carriage return in domain', "nomailbox@fabrikam\r.onmicrosoft.com"],
      ['array claim', ['nomailbox@fabrikam.onmicrosoft.com']],
      ['object claim', { email: 'nomailbox@fabrikam.onmicrosoft.com' }],
    ].each do |label, value|
      it "redirects to invalid_email for #{label}" do
        setup_entra_mock_auth(email: value)
        expect { post_sso_callback }.not_to change { auth_db[:accounts].count }
        expect_auth_error_redirect('invalid_email')
      end
    end
  end

  describe 'email source contract' do
    [
      { email: 'shadow@fabrikam.onmicrosoft.com' },
      { preferred_username: 'no.mailbox@fabrikam.onmicrosoft.com' },
      { upn: 'no.mailbox@fabrikam.onmicrosoft.com' },
    ].each do |claims|
      it "does not substitute raw_info #{claims.keys.first} for missing info.email" do
        setup_entra_mock_auth(email: nil, raw_info: claims)
        post_sso_callback
        expect_auth_error_redirect('missing_email')
      end
    end
  end

  describe 'email-shaped values are accepted' do
    # #4726: a mixed-case claim was persisted with the provider's casing, so
    # session sync missed the case-folded Customer and the callback redirected
    # without a session. The account now stores the normalized address.
    it 'creates an account and successful session for the original uppercase #EXT# guest UPN' do
      claim = 'alice_contoso.com#EXT#@fabrikam.onmicrosoft.com'
      uid = "uppercase-guest-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: claim, uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: 'alice_contoso.com#ext#@fabrikam.onmicrosoft.com', uid: uid)
    end

    it 'creates an account and successful session for an uppercase email' do
      local = "alice-#{SecureRandom.hex(6)}"
      uid = "uppercase-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: "#{local.upcase}@CONTOSO.COM", uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: "#{local}@contoso.com", uid: uid)
    end

    it 'signs a mixed-case returning identity into the same account and Customer' do
      local = "returning-#{SecureRandom.hex(6)}"
      uid = "uppercase-returning-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: "#{local.upcase}@Contoso.com", uid: uid)
      post_sso_callback
      account = expect_created_account(email: "#{local}@contoso.com", uid: uid)

      clear_cookies
      setup_entra_mock_auth(email: "#{local}@CONTOSO.COM", uid: uid)
      expect { post_sso_callback }.not_to change { auth_db[:accounts].count }
      expect(expect_created_account(email: "#{local}@contoso.com", uid: uid)[:id]).to eq(account[:id])
    end

    it 'creates an account and successful session for a one-letter TLD' do
      email = "alice-#{SecureRandom.hex(6)}@contoso.c"
      uid = "short-tld-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: email, uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: email, uid: uid)
    end

    it 'creates an account and successful session for a normalized email-shaped Entra B2B guest UPN' do
      email = "alice_#{SecureRandom.hex(6)}" + '_contoso.com#ext#@fabrikam.onmicrosoft.com'
      uid = "guest-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: email, uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: email, uid: uid)
    end

    it 'creates an account with a whitespace-padded valid email trimmed before persistence' do
      email = "alice-#{SecureRandom.hex(6)}@contoso.com"
      uid = "padded-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: " \t#{email}\r\n ", uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: email, uid: uid)
    end
  end

  # Lowercasing is case mapping, not normalize_email's case folding: folding
  # would turn straße.example.com into strasse.example.com before the gates.
  describe 'case folding' do
    let(:email) { "user-#{SecureRandom.hex(6)}@straße.example.com" }
    let(:uid) { "fold-#{SecureRandom.uuid}" }

    it 'judges the signup domain the IdP asserted, not its folded form' do
      configure_allowed_domains(['strasse.example.com'])
      setup_entra_mock_auth(email: email, uid: uid)
      expect { post_sso_callback }.not_to change { auth_db[:accounts].count }
      expect_auth_error_redirect('domain_not_allowed')
    end

    it 'stores the asserted address unfolded and signs in through the stored link' do
      setup_entra_mock_auth(email: email, uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      account = expect_provisioned_account(email: email, uid: uid)
      expect(account[:external_id]).not_to be_nil
      expect(last_request.env['rack.session'].to_h)
        .to include('authenticated' => true, 'account_id' => account[:id], 'external_id' => account[:external_id])
    end
  end

  describe 'Unicode surrounding whitespace' do
    it 'persists a trimmed email rather than a Unicode-padded mailbox' do
      email = unique_test_email('unicode-padded')
      uid = "unicode-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: "\u00a0#{email}\u2003", uid: uid)
      expect { post_sso_callback }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: email, uid: uid)
    end
  end

  describe 'linked platform identity' do
    it 'signs in on a subsequent callback without an email claim or another account' do
      email = unique_test_email('linked-noemail')
      uid = "linked-#{SecureRandom.uuid}"
      setup_mock_auth(email: email, uid: uid)
      post_sso_callback
      account = expect_created_account(email: email, uid: uid)

      clear_cookies
      setup_mock_auth(email: nil, uid: uid)
      # Signup policy must not become a sign-in policy for a linked platform user.
      configure_allowed_domains(['other.example.com'])
      expect { post_sso_callback }.not_to change { auth_db[:accounts].count }
      expect(last_response.status).to eq(302), last_response.body
      expect(last_request.env['rack.session'].to_h)
        .to include('authenticated' => true, 'account_id' => account[:id], 'email' => email)
      expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).all)
        .to contain_exactly(hash_including(account_id: account[:id]))
    end
  end

  describe 'tenant email allowlist', :oauth_flow do
    include_context 'domains enabled'

    let(:host) { "email-#{SecureRandom.hex(6)}.tenant.example.com" }
    let(:uid) { "tenant-#{SecureRandom.uuid}" }
    let(:email) { unique_test_email('tenant-email') }
    let(:tenant) { setup_oauth_test_domain(host) }

    before do
      tenant[:sso_config].allowed_domains = [email.split('@').last]
      tenant[:sso_config].save
    end

    def tenant_callback(claim)
      setup_mock_auth(email: claim, uid: uid)
      clear_body_headers
      header 'Host', host
      post '/auth/sso/oidc'
      expect(last_response.status).to eq(302), last_response.body
      expect(last_request.env['rack.session']['omniauth_tenant_domain_id'])
        .to eq(tenant[:domain].identifier)
      post_sso_callback
    end

    [false, true].each do |returning|
      context returning ? 'returning identity' : 'new identity' do
        before do
          next unless returning

          tenant_callback(email)
          expect_created_account(email: email, uid: uid)
          clear_cookies
        end

        [
          [nil, 'missing_email'],
          ['', 'missing_email'],
          [" \t\n", 'missing_email'],
          ["\u00a0", 'missing_email'],
          ['not-an-email', 'invalid_email'],
          ['attacker@evil.com@example.com', 'invalid_email'],
          [['user@example.com'], 'invalid_email'],
          ['user@disallowed.example.com', 'domain_not_allowed'],
        ].each do |claim, error|
          it "rejects #{claim.inspect} with #{error} without changing accounts or identities" do
            accounts_before = auth_db[:accounts].all
            identities_before = auth_db[:account_identities].all
            tenant_callback(claim)
            expect_auth_error_redirect(error)
            expect(auth_db[:accounts].all).to eq(accounts_before)
            expect(auth_db[:account_identities].all).to eq(identities_before)
            expect(last_request.env['rack.session']['authenticated']).not_to be(true)
          end
        end
      end
    end

    it 'denies a returning user after their domain is removed from the allowlist' do
      tenant_callback(email)
      account = expect_created_account(email: email, uid: uid)
      clear_cookies
      tenant[:sso_config].allowed_domains = ['another.example.com']
      tenant[:sso_config].save
      tenant_callback(email)
      expect_auth_error_redirect('domain_not_allowed')
      expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).all)
        .to contain_exactly(hash_including(account_id: account[:id]))
    end

    it 'allows a linked returning user without email when no tenant allowlist is configured' do
      tenant_callback(email)
      account = expect_created_account(email: email, uid: uid)
      clear_cookies
      tenant[:sso_config].allowed_domains = []
      tenant[:sso_config].save
      tenant_callback(nil)
      expect(last_response.status).to eq(302), last_response.body
      expect(last_request.env['rack.session'].to_h)
        .to include('authenticated' => true, 'account_id' => account[:id])
    end
  end

  describe 'via the Entra provider route' do
    [
      [nil, 'missing_email'],
      ['   ', 'missing_email'],
      ['not-an-email', 'invalid_email'],
    ].each do |email, error|
      it "redirects to #{error} for #{email.inspect}" do
        setup_entra_mock_auth(email: email, provider: :entra)
        expect { post_sso_callback(:entra) }.not_to change { auth_db[:accounts].count }
        expect_auth_error_redirect(error)
      end
    end

    it 'creates an account with a padded Entra email trimmed before persistence' do
      email = "entra-#{SecureRandom.hex(6)}@contoso.com"
      uid = "entra-#{SecureRandom.uuid}"
      setup_entra_mock_auth(email: "  #{email}  ", provider: :entra, uid: uid)
      expect { post_sso_callback(:entra) }.to change { auth_db[:accounts].count }.by(1)
      expect_created_account(email: email, uid: uid, provider: 'entra')
    end
  end
end
