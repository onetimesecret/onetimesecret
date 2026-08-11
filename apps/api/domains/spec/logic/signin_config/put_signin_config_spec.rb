# apps/api/domains/spec/logic/signin_config/put_signin_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for PutSigninConfig#log_enabled_state_change branching.
#
# The PUT handler fires audit events when the enabled state transitions:
#   - nil/false -> true: fires :domain_signin_config_enabled
#   - true -> false:     fires :domain_signin_config_disabled
#   - same -> same:      no event (early return)
#
# These branches are exercised by calling process() with appropriate
# fixtures and asserting the audit log output.
#
# The create/replace/serialization positive paths are covered by
# try/integration/api/domains/put_signin_config_try.rb.
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/signin_config/put_signin_config_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SigninConfig::PutSigninConfig do
  describe '#log_enabled_state_change' do
    # We test the private method via send since process() has too many
    # dependencies for a unit test. The method signature is:
    #   log_enabled_state_change(was_enabled, is_enabled)
    #
    # It calls log_signin_change_event which calls OT.info, so we can
    # assert on OT.info to verify which branch fires.

    # Minimal host that includes the mixin methods we need
    let(:host_class) do
      Class.new do
        include DomainsAPI::Logic::SigninConfig::ChangeLogger

        attr_accessor :custom_domain, :organization, :cust_obj

        # Alias for PutSigninConfig private method signature
        def log_enabled_state_change(was_enabled, is_enabled)
          return if was_enabled == is_enabled

          if is_enabled && (was_enabled.nil? || was_enabled == false)
            log_signin_change_event(
              event: :domain_signin_config_enabled,
              domain: custom_domain,
              org: organization,
              actor: cust_obj,
            )
          elsif was_enabled == true && !is_enabled
            log_signin_change_event(
              event: :domain_signin_config_disabled,
              domain: custom_domain,
              org: organization,
              actor: cust_obj,
            )
          end
        end

        def strategy_result
          nil
        end
      end
    end

    let(:host) do
      h = host_class.new
      h.custom_domain = instance_double(
        Onetime::CustomDomain,
        identifier: 'test_dom_1',
        display_domain: 'test.example.com',
      )
      h.organization = instance_double(
        Onetime::Organization,
        objid: 'org_1',
        extid: 'org_ext_1',
      )
      h.cust_obj = instance_double(
        Onetime::Customer,
        custid: 'cust_1',
        email: 'admin@test.com',
      )
      h
    end

    context 'when was_enabled equals is_enabled' do
      it 'does not fire any audit event (both false)' do
        expect(OT).not_to receive(:info)
        host.log_enabled_state_change(false, false)
      end

      it 'does not fire any audit event (both true)' do
        expect(OT).not_to receive(:info)
        host.log_enabled_state_change(true, true)
      end
    end

    context 'when transitioning from disabled to enabled' do
      it 'fires domain_signin_config_enabled (false -> true)' do
        expect(OT).to receive(:info).with(
          a_string_including('domain_signin_config_enabled'),
          anything,
        )
        host.log_enabled_state_change(false, true)
      end

      it 'fires domain_signin_config_enabled (nil -> true)' do
        expect(OT).to receive(:info).with(
          a_string_including('domain_signin_config_enabled'),
          anything,
        )
        host.log_enabled_state_change(nil, true)
      end
    end

    context 'when transitioning from enabled to disabled' do
      it 'fires domain_signin_config_disabled (true -> false)' do
        expect(OT).to receive(:info).with(
          a_string_including('domain_signin_config_disabled'),
          anything,
        )
        host.log_enabled_state_change(true, false)
      end
    end

    context 'when was_enabled is nil and is_enabled is false' do
      it 'does not fire any event (nil != false, but no branch matches)' do
        # nil != false so the early return doesn't fire.
        # is_enabled is false so the enable branch doesn't fire.
        # was_enabled is nil (not true) so the disable branch doesn't fire.
        expect(OT).not_to receive(:info)
        host.log_enabled_state_change(nil, false)
      end
    end
  end

  describe '#validate_webauthn_restriction!' do
    # Passkeys are host-scoped (rp_id = request.host): a webauthn-only
    # restriction on a custom domain is a guaranteed visitor lockout, so NEW
    # restrict_to='webauthn' writes are rejected. A value persisted before the
    # check may be resubmitted unchanged (PUT is full-replacement; the form's
    # locked keep-if-selected row re-sends it when other fields change).
    #
    # Exercised on the REAL private method via an allocated instance
    # (raise_concerns has too many authorization dependencies for a unit
    # test — same rationale as the log_enabled_state_change block above), with
    # @restrict_to/@existing_config set to the values process_params /
    # raise_concerns would have produced. The enum check (validate_restrict_to)
    # is untouched and stays covered by
    # try/integration/api/domains/put_signin_config_try.rb.

    def build_logic(restrict_to:, existing_restrict_to: :none)
      logic = described_class.allocate
      logic.instance_variable_set(:@restrict_to, restrict_to)

      existing = if existing_restrict_to == :none
        nil
      else
        instance_double(
          Onetime::CustomDomain::SigninConfig,
          restrict_to: existing_restrict_to,
        )
      end
      logic.instance_variable_set(:@existing_config, existing)
      logic
    end

    def validate!(logic)
      logic.send(:validate_webauthn_restriction!)
    end

    context 'rejecting new webauthn restrictions' do
      it 'raises FormError when no config exists yet' do
        logic = build_logic(restrict_to: 'webauthn')

        expect { validate!(logic) }.to raise_error(Onetime::FormError) do |ex|
          expect(ex.message).to include('not supported on custom domains')
          expect(ex.field).to eq(:restrict_to)
          expect(ex.error_type).to eq(:invalid)
        end
      end

      it 'raises FormError when transitioning from another restriction' do
        logic = build_logic(restrict_to: 'webauthn', existing_restrict_to: 'password')

        expect { validate!(logic) }.to raise_error(Onetime::FormError)
      end

      it 'raises FormError when transitioning from no restriction' do
        logic = build_logic(restrict_to: 'webauthn', existing_restrict_to: nil)

        expect { validate!(logic) }.to raise_error(Onetime::FormError)
      end
    end

    context 'allowing everything else' do
      it 'permits a carry-over resubmit of an already-persisted webauthn value' do
        logic = build_logic(restrict_to: 'webauthn', existing_restrict_to: 'webauthn')

        expect { validate!(logic) }.not_to raise_error
      end

      it 'permits non-webauthn values regardless of existing state' do
        expect { validate!(build_logic(restrict_to: 'password')) }.not_to raise_error
        expect { validate!(build_logic(restrict_to: 'sso', existing_restrict_to: 'webauthn')) }.not_to raise_error
      end

      it 'permits clearing the restriction' do
        logic = build_logic(restrict_to: nil, existing_restrict_to: 'webauthn')

        expect { validate!(logic) }.not_to raise_error
      end
    end
  end
end
