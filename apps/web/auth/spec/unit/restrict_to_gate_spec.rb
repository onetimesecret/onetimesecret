# apps/web/auth/spec/unit/restrict_to_gate_spec.rb
#
# frozen_string_literal: true

# Unit tests for the restrict_to route gate
# (ADR-034#restrict-to-is-an-access-control-not-a-display-preference /
# #reject-as-not-found-not-forbidden, #4139).
#
# WHY THIS EXISTS ALONGSIDE THE INTEGRATION SPEC. The integration spec
# (spec/integration/full/restrict_to_enforcement_spec.rb) can only exercise
# routes that are actually MOUNTED, and the full-mode lane boots with
# email_auth and webauthn disabled (spec/support/auth_mode_helpers.rb's
# MockAuthConfig defaults them off), so their endpoints are absent and those
# examples skip. That is exactly the coverage
# ADR-034#reject-as-not-found-not-forbidden says must not be missing —
# the secondary endpoints. Here the routing decision is exercised directly
# against @current_route, so every gated route symbol is covered regardless of
# which features a lane happens to load.
#
# No Valkey and no HTTP: resolution is stubbed, because resolution itself is
# the model's (SigninConfig.resolve_restrict_to) and is tested there. What is
# under test is the MAPPING from route to sign-in method and the halt.
#
# Run:
#   bundle exec rspec apps/web/auth/spec/unit/restrict_to_gate_spec.rb

require_relative '../spec_helper'

# The POLICY module only — deliberately NOT config/hooks/restrict_to.rb, which
# is namespaced into Auth::Config and would drag the whole boot chain in. That
# separation is the reason apps/web/auth/restrict_to.rb exists; this require is
# also the assertion that it holds.
require_relative '../../restrict_to'

RSpec.describe Auth::RestrictTo do
  let(:resolution_class) { Onetime::CustomDomain::SigninConfig::RestrictToResolution }

  # Minimal stand-in for the Rodauth instance the hook block runs against:
  # current_route, request.env, request.path and the halt. `internal_request?`
  # is private on the real object, which is why the gate reaches it with send —
  # the double mirrors that.
  def rodauth_double(route, internal: false, features: [])
    request = double('request', env: { 'onetime.display_domain' => 'tenant.example.com' }, path: "/#{route}")
    allow(request).to receive(:halt) { |response| throw :halted, response }

    instance = double('rodauth', current_route: route, request: request, features: features)
    allow(instance).to receive(:send).with(:internal_request?).and_return(internal)
    instance
  end

  # Runs the gate and returns the halt response, or nil when it allowed through.
  def gate(route, resolution, internal: false, features: [])
    allow(described_class).to receive(:resolution_for).and_return(resolution)

    catch(:halted) do
      described_class.enforce_route!(rodauth_double(route, internal: internal, features: features))
      nil
    end
  end

  describe 'route → sign-in method mapping' do
    # The table is the policy. Asserting it here (rather than only through
    # mounted routes) is what makes the webauthn and email_auth entries real
    # coverage in every lane.
    {
      'password' => %i[login create_account reset_password_request reset_password
                       verify_account verify_account_resend],
      'email_auth' => %i[email_auth_request email_auth],
      # webauthn_auth / webauthn_auth_js are deliberately absent: they are the
      # SECOND-FACTOR ceremony, exempt per
      # ADR-034#reject-as-not-found-not-forbidden. Covered instead by the
      # UNGATED_ROUTES assertion below, which asserts they are never rejected.
      'webauthn' => %i[webauthn_login webauthn_autofill_js],
    }.each do |method_name, routes|
      routes.each do |route|
        it "404s #{route} when the host permits only a different method" do
          other      = method_name == 'password' ? 'sso' : 'password'
          halted     = gate(route, resolution_class.restricted(other, :domain))
          status, _h, body = halted

          expect(status).to eq(404), "#{route} was not rejected on a host restricted to #{other}"
          expect(JSON.parse(body.first)['error_type']).to eq('NotFound')
        end

        it "allows #{route} when the host permits #{method_name}" do
          expect(gate(route, resolution_class.restricted(method_name, :domain))).to be_nil
        end
      end
    end
  end

  describe 'webauthn_verify_account signup routes' do
    let(:features) { [:webauthn_verify_account] }

    described_class::WEBAUTHN_VERIFY_ACCOUNT_ROUTES.each do |route|
      it "allows #{route} on a WebAuthn-only host" do
        resolution = resolution_class.restricted('webauthn', :global)

        expect(gate(route, resolution, features: features)).to be_nil
      end

      it "404s #{route} on a password-only host" do
        resolution = resolution_class.restricted('password', :global)

        expect(gate(route, resolution, features: features)&.first).to eq(404)
      end
    end
  end

  describe 'resolution states' do
    it 'allows every route when unrestricted' do
      described_class::GATED_ROUTES.each_key do |route|
        expect(gate(route, resolution_class.unrestricted(:global))).to be_nil,
          "#{route} was rejected on an unrestricted host"
      end
    end

    it 'rejects every route when the restriction is unavailable (A3 fail-closed)' do
      described_class::GATED_ROUTES.each_key do |route|
        halted = gate(route, resolution_class.unavailable('sso', :global))

        expect(halted&.first).to eq(404), "#{route} was allowed while sign-in is unavailable"
      end
    end
  end

  describe 'routes outside the gate' do
    it 'never touches an ungated route, whatever the restriction' do
      described_class::UNGATED_ROUTES.each do |route|
        expect(gate(route, resolution_class.restricted('sso', :domain))).to be_nil,
          "#{route} is documented as exempt (account-scoped / not a sign-in method) but was rejected"
      end
    end

    it 'never touches logout' do
      expect(gate(:logout, resolution_class.unavailable('sso', :global))).to be_nil
    end
  end

  describe 'internal requests' do
    # Rodauth's internal_request feature calls before_rodauth directly with a
    # synthesized env that has no Host at all. Gating those would break
    # server-initiated app flows (invite signup autologin) for a policy about
    # request hosts they do not have.
    it 'is skipped for internal requests' do
      expect(gate(:login, resolution_class.restricted('sso', :domain), internal: true)).to be_nil
    end
  end

  describe '.allows?' do
    it 'is the entry point for the non-Rodauth surfaces (SSO, linking routes)' do
      allow(described_class).to receive(:resolution_for)
        .and_return(resolution_class.restricted('sso', :domain))

      expect(described_class.allows?({}, 'sso')).to be true
      expect(described_class.allows?({}, 'password')).to be false
    end
  end

  describe '.resolution_for custom-host capability' do
    let(:domain_id) { 'domain-4139' }
    let(:env) do
      {
        'onetime.display_domain' => 'tenant.example.com',
        'onetime.domain_strategy' => :custom,
      }
    end
    let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('tenant.example.com').and_return(custom_domain)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with(domain_id).and_return(nil)
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('sso')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_restriction_available?)
        .with('sso').and_return(true)
    end

    it 'fails an inherited SSO restriction closed when this host has no usable SSO path' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
        .with(domain_id).and_return(false)

      expect(described_class.resolution_for(env)).to be_unavailable
    end

    it 'keeps an inherited SSO restriction when the host predicate finds tenant or platform-fallback SSO' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
        .with(domain_id).and_return(true)

      resolution = described_class.resolution_for(env)

      expect(resolution).to be_restricted
      expect(resolution.allows?('sso')).to be(true)
    end
  end

  # An unreadable policy is not a policy. Three reads on the hot path of every
  # custom-host request can raise — the CustomDomain identity, the SigninConfig,
  # the SSO probes — and when one does, the gate does not know what this host
  # permits. It answers by raising, and the edge renders 503.
  #
  # NO GUESSING IN EITHER DIRECTION, which is what the cases below pin. An
  # earlier cut of #4139 keyed the answer on the GLOBAL value: fail closed when
  # something was globally restricted, degrade to :unrestricted when nothing
  # was. That reads as prudent and is not — the global value describes the
  # install, not this host, so on an install with no global restriction a blip
  # silently dropped the per-domain gate and served every method the domain
  # config exists to hide. The objection it was protecting against (mystery
  # 404s on an unrestricted install) is answered by the 503, not by widening.
  describe '.resolution_for lookup failures' do
    let(:custom_env) do
      {
        'onetime.display_domain' => 'tenant.example.com',
        'onetime.domain_strategy' => :custom,
      }
    end

    before do
      allow(Auth::Logging).to receive(:log_auth_event)
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('password')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_restriction_available?).and_return(true)
    end

    it 'fails closed when the classified custom host cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

      expect { described_class.resolution_for(custom_env) }
        .to raise_error(Onetime::SigninPolicyUnavailable)
    end

    it 'fails closed when the classified custom host signin config lookup fails' do
      domain = instance_double(Onetime::CustomDomain, identifier: 'domain-4139')
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(domain)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with('domain-4139').and_raise(Redis::BaseError, 'config unavailable')

      expect { described_class.resolution_for(custom_env) }
        .to raise_error(Onetime::SigninPolicyUnavailable)
    end

    it 'fails closed on the SSO probe too — that read is on the hot path of every request' do
      domain = instance_double(Onetime::CustomDomain, identifier: 'domain-4139')
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(domain)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with('domain-4139').and_return(nil)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:sso_available_for_tenant_host?)
        .and_raise(Redis::BaseError, 'sso probe unavailable')

      expect { described_class.resolution_for(custom_env) }
        .to raise_error(Onetime::SigninPolicyUnavailable)
    end

    it 'logs the failure — an auth surface is down and it must alert' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

      expect { described_class.resolution_for(custom_env) }
        .to raise_error(Onetime::SigninPolicyUnavailable)

      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:restrict_to_domain_lookup_failed, hash_including(level: :error))
    end

    it 'carries a retry_after so the edge can hint a back-off' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

      expect { described_class.resolution_for(custom_env) }
        .to raise_error(Onetime::SigninPolicyUnavailable) { |ex|
          expect(ex.to_h[:error_type]).to eq('SigninPolicyUnavailable')
          expect(ex.to_h[:retry_after]).to be_a(Integer)
        }
    end

    # The widen an earlier cut of this gate allowed, pinned as a rejection: the
    # install restricts nothing globally, so the OLD rule degraded to
    # :unrestricted and served the very methods a per-domain restriction we
    # never got to read may have hidden.
    context 'with NO restriction configured globally' do
      before { allow(Onetime.auth_config).to receive(:restrict_to).and_return(nil) }

      it 'still fails closed — a blank global says nothing about this host' do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

        expect { described_class.resolution_for(custom_env) }
          .to raise_error(Onetime::SigninPolicyUnavailable)
      end
    end

    # The carve-out below is a positive test for an OPERATOR host, not
    # `!= :custom`. A host DomainStrategy could not classify answers :invalid —
    # which is exactly what a failing domain-index read produces for a host
    # that IS a custom domain — so it must fail closed with the rest.
    it 'fails closed on a host that could not be classified' do
      unclassified_env = {
        'onetime.display_domain' => 'tenant.example.com',
        'onetime.domain_strategy' => :invalid,
      }
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('tenant.example.com').and_raise(Redis::BaseError, 'lookup unavailable')

      expect { described_class.resolution_for(unclassified_env) }
        .to raise_error(Onetime::SigninPolicyUnavailable)
    end

    it 'preserves global fallback semantics for a non-custom host lookup failure' do
      canonical_env = {
        'onetime.display_domain' => 'example.com',
        'onetime.domain_strategy' => :canonical,
      }
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('example.com').and_raise(Redis::BaseError, 'lookup unavailable')
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('password')
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_restriction_available?)
        .with('password').and_return(true)

      resolution = described_class.resolution_for(canonical_env)

      expect(resolution).to be_restricted
      expect(resolution.allows?('password')).to be(true)
    end
  end
end
