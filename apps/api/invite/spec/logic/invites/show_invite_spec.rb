# apps/api/invite/spec/logic/invites/show_invite_spec.rb
#
# frozen_string_literal: true

# ShowInvite Endpoint Specification
#
# GET /api/invite/:token
#
# Auth: noauth (the invite token is the only credential).
#
# This spec covers the ADR-024 A11 (#4139) addition: the response carries the
# request host's `restrict_to` resolution, so the invite page can tell in
# advance which sign-in/sign-up methods that host will accept. Without it the
# page renders a password signup form whose submit 404s at the A11 gate on
# POST /:token/signup.
#
# Run: pnpm run test:rspec apps/api/invite/spec/logic/invites/show_invite_spec.rb

require_relative '../../spec_helper'

RSpec.describe InviteAPI::Logic::Invites::ShowInvite do
  let(:organization) do
    build_mock_organization(
      objid: 'org-test-456',
      extid: 'org-ext-test-456',
      display_name: 'Test Organization'
    )
  end

  let(:invited_email) { 'invitee@example.com' }
  let(:invite_token) { SecureRandom.hex(24) }

  let(:invitation) do
    build_mock_invitation(
      objid: 'inv-show-123',
      token: invite_token,
      invited_email: invited_email,
      role: 'member',
      organization: organization,
      organization_objid: 'org-test-456',
      'pending?' => true,
      'expired?' => false
    )
  end

  let(:session) { {} }
  let(:client_ip) { '192.168.1.100' }
  let(:rate_limiter) { instance_double(Onetime::Security::InviteTokenRateLimiter) }

  # Host context. Overridden per-context to move between the canonical host
  # and a custom domain.
  let(:domain_strategy) { :canonical }
  let(:display_domain)  { 'onetimesecret.com' }

  let(:strategy_result) do
    build_strategy_result(
      session: session,
      user: nil,
      authenticated: false,
      metadata: {
        ip: client_ip,
        domain_strategy: domain_strategy,
        display_domain: display_domain,
      }
    )
  end

  let(:params) { { 'token' => invite_token } }

  subject(:logic) { described_class.new(strategy_result, params) }

  # Resolution helper. Drives the endpoint with REAL RestrictToResolution
  # values so the semantics under test stay the model's (A2): in particular
  # #allows? returning false for everything in the :unavailable state.
  def resolution_for(state, value, source)
    klass = Onetime::CustomDomain::SigninConfig::RestrictToResolution
    case state
    when :unrestricted then klass.unrestricted(source)
    when :restricted   then klass.restricted(value, source)
    when :unavailable  then klass.unavailable(value, source)
    end
  end

  let(:resolution) { resolution_for(:unrestricted, nil, :global) }

  before do
    allow(Onetime::Security::InviteTokenRateLimiter).to receive(:new)
      .with(client_ip)
      .and_return(rate_limiter)
    allow(rate_limiter).to receive(:check!)
    allow(rate_limiter).to receive(:record_attempt)
    allow(Onetime::OrganizationMembership).to receive(:find_by_token)
      .with(invite_token)
      .and_return(invitation)

    # Stub at the INPUT-GATHERING seam only. Auth::RestrictTo.resolution_for
    # reads live per-host state (CustomDomain + SigninConfig lookups); the
    # rule it feeds (SigninConfig.resolve_restrict_to) and the verdict object
    # stay real. Auth::RestrictTo.allows? is built on resolution_for, so the
    # A11 gate on POST /:token/signup reads the same stub — which is what
    # makes the agreement test below meaningful rather than circular.
    allow(Auth::RestrictTo).to receive(:resolution_for).and_return(resolution)
  end

  def record
    logic.raise_concerns
    logic.process[:record]
  end

  # ==========================================================================
  # effective_restrict_to (ADR-024 A11, #4139)
  # ==========================================================================

  describe 'effective_restrict_to' do
    context 'on an unrestricted host' do
      let(:resolution) { resolution_for(:unrestricted, nil, :global) }

      it 'reports unrestricted with a null method' do
        expect(record[:effective_restrict_to]).to eq(
          state: 'unrestricted', restrict_to: nil, source: 'global'
        )
      end
    end

    context 'when the restriction comes from the domain' do
      let(:resolution) { resolution_for(:restricted, 'sso', :domain) }

      it 'reports the method and names the domain as the source' do
        expect(record[:effective_restrict_to]).to eq(
          state: 'restricted', restrict_to: 'sso', source: 'domain'
        )
      end
    end

    context 'when the restriction comes from the install (global)' do
      let(:resolution) { resolution_for(:restricted, 'sso', :global) }

      it 'reports the method and names global as the source' do
        expect(record[:effective_restrict_to]).to eq(
          state: 'restricted', restrict_to: 'sso', source: 'global'
        )
      end
    end

    context 'when the restricted method is unavailable (A3 fail-closed)' do
      let(:resolution) { resolution_for(:unavailable, 'sso', :domain) }

      # The three-state shape survives the wire: :unavailable is NOT projected
      # down to a bare null the way `features.restrict_to` must be. A null
      # here would read as "unrestricted" and re-offer every method the
      # restriction hid — the fail-open A3 exists to kill.
      it 'reports unavailable, keeping the method that was named' do
        expect(record[:effective_restrict_to]).to eq(
          state: 'unavailable', restrict_to: 'sso', source: 'domain'
        )
      end
    end

    context 'when global and domain restrictions conflict (A8)' do
      let(:resolution) { resolution_for(:unavailable, 'sso', :conflict) }

      it 'reports unavailable with source conflict' do
        expect(record[:effective_restrict_to]).to eq(
          state: 'unavailable', restrict_to: 'sso', source: 'conflict'
        )
      end
    end

    # THE REGRESSION THAT MOTIVATED THE FIELD. auth_methods sits inside the
    # `custom_domain?` branch, so an SSO-only INSTALL — A11's stated live case,
    # where the restriction is global and the invitee is on the canonical host
    # — used to receive nothing at all to predict the gate with.
    context 'on a NON-custom host' do
      let(:domain_strategy) { :canonical }
      let(:resolution) { resolution_for(:restricted, 'sso', :global) }

      it 'still emits effective_restrict_to' do
        expect(record).to include(:effective_restrict_to)
        expect(record[:effective_restrict_to][:restrict_to]).to eq('sso')
      end

      it 'emits no custom-domain payload' do
        expect(record).not_to include(:auth_methods)
        expect(record).not_to include(:branding)
      end
    end

    it 'resolves for the host THIS request arrived on' do
      # The logic layer receives a StrategyResult, not the Rack env, so it
      # rebuilds the two keys Auth::RestrictTo reads. A resolution computed
      # from anything other than the request host would disagree with the gate
      # on POST /:token/signup, which is judged against exactly this host.
      expect(Auth::RestrictTo).to receive(:resolution_for).with(
        {
          'onetime.domain_strategy' => :canonical,
          'onetime.display_domain' => 'onetimesecret.com',
        }
      ).and_return(resolution)

      record
    end

    # AZ7. The endpoint is noauth: nothing in the response may vary on the
    # invitee or on whether their email already has an account. This field is
    # a property of the REQUEST HOST alone — the same value every visitor to
    # that host reads off `features.restrict_to` on its sign-in page.
    it 'does not vary with the invitee [AZ7]' do
      first = record

      other = build_mock_invitation(
        objid: 'inv-show-999',
        token: invite_token,
        invited_email: 'someone.else@example.com',
        role: 'admin',
        organization: organization,
        organization_objid: 'org-test-456',
        'pending?' => true,
        'expired?' => false
      )
      allow(Onetime::OrganizationMembership).to receive(:find_by_token)
        .with(invite_token).and_return(other)

      second = described_class.new(strategy_result, params)
      second.raise_concerns

      expect(second.process[:record][:effective_restrict_to]).to eq(first[:effective_restrict_to])
    end
  end

  # ==========================================================================
  # auth_methods filtering (ADR-024 A1)
  # ==========================================================================

  describe 'auth_methods on a custom domain' do
    let(:domain_strategy) { :custom }
    let(:display_domain)  { 'signin.acme.example' }

    let(:sso_config) do
      instance_double(
        Onetime::CustomDomain::SsoConfig,
        'enabled?' => true,
        provider_type: 'oidc',
        display_name: 'Acme SSO',
        platform_route_name: 'acme-oidc'
      )
    end

    let(:custom_domain) do
      instance_double(
        Onetime::CustomDomain,
        identifier: 'domain-acme-123',
        display_domain: display_domain,
        sso_config: sso_config,
        brand_settings: nil
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(display_domain).and_return(custom_domain)
      allow(Onetime.auth_config).to receive(:email_auth_enabled?).and_return(true)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
        .with('domain-acme-123', sso_config: sso_config)
        .and_return(true)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
        .with('domain-acme-123')
        .and_return(true)
    end

    context 'unrestricted' do
      let(:resolution) { resolution_for(:unrestricted, nil, :global) }

      it 'offers every enabled method' do
        expect(record[:auth_methods].map { |m| m[:type] }).to contain_exactly('password', 'magic_link', 'sso')
      end
    end

    context 'restricted to sso' do
      let(:resolution) { resolution_for(:restricted, 'sso', :domain) }

      it 'offers sso alone — never a method the host will reject' do
        expect(record[:auth_methods].map { |m| m[:type] }).to eq(['sso'])
      end

      # The frontend routes the invitee to THIS tenant's SSO with these two
      # fields; the bootstrap `features` payload does not carry them, so
      # filtering must not flatten the entry.
      it 'keeps platform_route_name and display_name on the surviving entry' do
        sso = record[:auth_methods].find { |m| m[:type] == 'sso' }
        expect(sso).to include(platform_route_name: 'acme-oidc', display_name: 'Acme SSO')
      end

      it 'checks the tenant route through the runtime availability ladder' do
        expect(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
          .with('domain-acme-123', sso_config: sso_config)
          .and_return(true)

        expect(record[:auth_methods].map { |method| method[:type] }).to eq(['sso'])
      end

      context 'when the stored tenant config is enabled but unavailable at runtime' do
        before do
          allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
            .and_return(false)
        end

        it 'does not advertise the unusable tenant route' do
          allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
            .and_return(false)

          expect(record[:auth_methods]).to eq([])
        end

        it 'serializes usable platform fallback providers instead' do
          allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
            .with('domain-acme-123')
            .and_return(true)
          allow(Onetime.auth_config).to receive(:sso_providers).and_return([
            { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
            { 'route_name' => 'github', 'display_name' => 'GitHub' },
          ])

          expect(record[:auth_methods]).to include(
            include(type: 'sso', platform_route_name: 'oidc', display_name: 'Platform SSO'),
            include(type: 'sso', platform_route_name: 'github', display_name: 'GitHub'),
          )
          expect(record[:auth_methods]).not_to include(
            include(platform_route_name: 'acme-oidc')
          )
        end

        # Shape pin for the fallback arm. It is NOT the tenant arm's shape:
        # :provider_type is absent because AuthConfig#sso_providers has no such
        # key and the platform registry's vocabulary (oidc, entra, google,
        # github) is not tenant PROVIDER_TYPES (oidc, entra_id). What both arms
        # do share is :platform_route_name — the field the frontend routes on
        # (AcceptInvite.vue#ssoMethods filters on exactly that), so the
        # asymmetry is invisible to the consumer that matters.
        it 'emits routable entries without a tenant provider_type' do
          allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
            .with('domain-acme-123')
            .and_return(true)
          allow(Onetime.auth_config).to receive(:sso_providers).and_return([
            { 'route_name' => 'entra', 'display_name' => 'Microsoft' },
          ])

          expect(record[:auth_methods]).to eq([
            { type: 'sso', enabled: true, platform_route_name: 'entra', display_name: 'Microsoft' },
          ])
          expect(record[:auth_methods].first).not_to have_key(:provider_type)
        end

        # A provider with no route name is unroutable: advertising it would
        # render a button with nowhere to send the invitee.
        it 'drops a provider with a blank route_name' do
          allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
            .with('domain-acme-123')
            .and_return(true)
          allow(Onetime.auth_config).to receive(:sso_providers).and_return([
            { 'route_name' => '', 'display_name' => 'Broken' },
            { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
          ])

          expect(record[:auth_methods].map { |method| method[:platform_route_name] }).to eq(['oidc'])
        end
      end
    end

    context 'restricted to password' do
      let(:resolution) { resolution_for(:restricted, 'password', :domain) }

      it 'drops magic_link and sso' do
        expect(record[:auth_methods].map { |m| m[:type] }).to eq(['password'])
      end
    end

    context "restricted to email_auth (wire type 'magic_link')" do
      let(:resolution) { resolution_for(:restricted, 'email_auth', :domain) }

      # Naming seam: the restrict_to value is 'email_auth', the wire type is
      # 'magic_link'. Asking the resolution about 'magic_link' would silently
      # drop the one method the host does offer.
      it 'keeps magic_link' do
        expect(record[:auth_methods].map { |m| m[:type] }).to eq(['magic_link'])
      end
    end

    context 'unavailable (A3)' do
      let(:resolution) { resolution_for(:unavailable, 'sso', :domain) }

      # Empty is the correct answer: the frontend renders "sign-in
      # unavailable". Widening back to password/magic_link here would
      # re-expose exactly the methods the restriction hid.
      it 'offers nothing at all' do
        expect(record[:auth_methods]).to eq([])
      end
    end

    it 'never advertises a method the resolution disallows' do
      %w[password email_auth sso].each do |method_name|
        res = resolution_for(:restricted, method_name, :domain)
        allow(Auth::RestrictTo).to receive(:resolution_for).and_return(res)

        instance = described_class.new(strategy_result, params)
        instance.raise_concerns
        types = instance.process[:record][:auth_methods].map { |m| m[:type] }

        types.each do |type|
          restrict_value = type == 'magic_link' ? 'email_auth' : type
          expect(res.allows?(restrict_value)).to be(true),
            "advertised #{type} on a host restricted to #{method_name}"
        end
      end
    end
  end

  # ==========================================================================
  # AGREEMENT: this endpoint's report matches the gate's behavior
  # ==========================================================================
  #
  # The whole point of the field. Both endpoints route through
  # Auth::RestrictTo for the SAME host: ShowInvite renders
  # resolution_for(env), the A11 gate on POST /:token/signup calls
  # allows?(env, 'password'), which is resolution_for(env).allows?('password').
  # Stubbing only resolution_for means a divergence in how either side
  # interprets the verdict shows up here.
  describe 'agreement with the POST /:token/signup gate (A11)' do
    let(:domain_strategy) { :custom }
    let(:display_domain)  { 'signin.acme.example' }
    let(:valid_password)  { 'SecureP@ssw0rd123!' }

    let(:signup_logic) do
      InviteAPI::Logic::Invites::SignupAndAccept.new(
        strategy_result,
        { 'token' => invite_token, 'password' => valid_password }
      )
    end

    before do
      allow(Onetime::Customer).to receive(:email_exists?).and_return(false)
      allow(Auth::Config).to receive(:create_account).and_return(nil)
      allow(Auth::Logging).to receive(:log_auth_event)
    end

    def signup_permitted?
      signup_logic.raise_concerns
      true
    rescue Onetime::RecordNotFound
      false
    end

    # THE OTHER HALF OF THE AGREEMENT, and the half the case list below cannot
    # reach: every case above stubs resolution_for regardless of its argument,
    # so a divergence in the ENV the two endpoints ask about would pass all of
    # them silently. That env used to be two byte-identical private copies of
    # the same hash (#4139); it is now one method on InviteAPI::Logic::Base.
    #
    # This example fails the moment either class reintroduces its own — which
    # is the concrete drift the hoist exists to prevent: ShowInvite would
    # report a verdict for one host while the gate judges another, and the
    # invite page would describe a password surface the POST 404s on.
    it 'asks about the SAME host the gate judges' do
      asked = []
      allow(Auth::RestrictTo).to receive(:resolution_for) do |env|
        asked << env
        resolution
      end

      record
      signup_permitted?

      expect(asked.length).to eq(2)
      expect(asked.first).to eq(asked.last)
      expect(asked.first).to eq(
        'onetime.domain_strategy' => :custom,
        'onetime.display_domain' => 'signin.acme.example'
      )
    end

    # And the source of that agreement is structural, not a convention two
    # files happen to share: both endpoints inherit one implementation.
    it 'derives that host from a single inherited implementation' do
      owner = ->(klass) { klass.instance_method(:restrict_to_env).owner }

      expect(owner.call(described_class)).to eq(InviteAPI::Logic::Base)
      expect(owner.call(InviteAPI::Logic::Invites::SignupAndAccept))
        .to eq(InviteAPI::Logic::Base)
    end

    # Every reachable resolution, including the two that fail closed.
    {
      'unrestricted'          => [:unrestricted, nil, :global],
      'restricted/password'   => [:restricted, 'password', :domain],
      'restricted/sso'        => [:restricted, 'sso', :domain],
      'restricted/email_auth' => [:restricted, 'email_auth', :domain],
      'restricted/webauthn'   => [:restricted, 'webauthn', :domain],
      'unavailable/domain'    => [:unavailable, 'sso', :domain],
      'unavailable/conflict'  => [:unavailable, 'sso', :conflict],
    }.each do |label, args|
      context "when the host resolves #{label}" do
        let(:resolution) { resolution_for(*args) }

        it 'reports a password surface exactly when the gate opens one' do
          reported = record[:effective_restrict_to]

          password_reported = case reported[:state]
                              when 'unrestricted' then true
                              when 'restricted'   then reported[:restrict_to] == 'password'
                              else false
                              end

          expect(password_reported).to eq(signup_permitted?),
            "ShowInvite reported #{reported.inspect} but the gate " \
            "#{signup_permitted? ? 'allowed' : 'refused'} signup"
        end
      end
    end
  end
end
