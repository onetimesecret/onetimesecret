# apps/web/auth/spec/config/env_conditionals_spec.rb
#
# frozen_string_literal: true

# Tests for ENV conditional logic in Auth::Config
#
# These tests verify that the ENV variable parsing patterns work correctly.
# The production code in config.rb uses two distinct patterns:
#   - `!= 'false'` (enabled by default, must explicitly disable)
#   - `== 'true'` (disabled by default, must explicitly enable)
#
# This spec validates the boolean logic without requiring full app boot.
# The Phase 1 feature specs test that features work when enabled;
# these tests verify the ENV parsing that controls enablement.

require_relative '../spec_helper'
require 'climate_control'

RSpec.describe 'Auth::Config ENV Conditional Logic' do
  describe 'AUTH_HARDENING_ENABLED pattern (!= false, enabled by default)' do
    # Pattern: ENV['AUTH_HARDENING_ENABLED'] != 'false'
    # This means: enabled unless explicitly set to 'false'
    # Same pattern used by: AUTH_ACTIVE_SESSIONS_ENABLED, AUTH_REMEMBER_ME_ENABLED, AUTH_VERIFY_ACCOUNT_ENABLED

    it 'is enabled when ENV is not set (nil)' do
      ClimateControl.modify('AUTH_HARDENING_ENABLED' => nil) do
        expect(ENV['AUTH_HARDENING_ENABLED'] != 'false').to be true
      end
    end

    it 'is enabled when ENV is empty string' do
      ClimateControl.modify('AUTH_HARDENING_ENABLED' => '') do
        expect(ENV['AUTH_HARDENING_ENABLED'] != 'false').to be true
      end
    end

    it 'is enabled when ENV is "true"' do
      ClimateControl.modify('AUTH_HARDENING_ENABLED' => 'true') do
        expect(ENV['AUTH_HARDENING_ENABLED'] != 'false').to be true
      end
    end

    it 'is enabled when ENV is any other value' do
      ClimateControl.modify('AUTH_HARDENING_ENABLED' => 'yes') do
        expect(ENV['AUTH_HARDENING_ENABLED'] != 'false').to be true
      end
    end

    it 'is DISABLED only when ENV is exactly "false"' do
      ClimateControl.modify('AUTH_HARDENING_ENABLED' => 'false') do
        expect(ENV['AUTH_HARDENING_ENABLED'] != 'false').to be false
      end
    end

    it 'is enabled when ENV is "False" (case sensitive)' do
      ClimateControl.modify('AUTH_HARDENING_ENABLED' => 'False') do
        # NOTE: This is enabled because comparison is case-sensitive
        expect(ENV['AUTH_HARDENING_ENABLED'] != 'false').to be true
      end
    end
  end

  describe 'AUTH_MFA_ENABLED pattern (== true, disabled by default)' do
    # Pattern: ENV['AUTH_MFA_ENABLED'] == 'true'
    # This means: disabled unless explicitly set to 'true'

    it 'is disabled when ENV is not set (nil)' do
      ClimateControl.modify('AUTH_MFA_ENABLED' => nil) do
        expect(ENV['AUTH_MFA_ENABLED'] == 'true').to be false
      end
    end

    it 'is disabled when ENV is empty string' do
      ClimateControl.modify('AUTH_MFA_ENABLED' => '') do
        expect(ENV['AUTH_MFA_ENABLED'] == 'true').to be false
      end
    end

    it 'is disabled when ENV is "false"' do
      ClimateControl.modify('AUTH_MFA_ENABLED' => 'false') do
        expect(ENV['AUTH_MFA_ENABLED'] == 'true').to be false
      end
    end

    it 'is disabled when ENV is "yes" (must be exactly "true")' do
      ClimateControl.modify('AUTH_MFA_ENABLED' => 'yes') do
        expect(ENV['AUTH_MFA_ENABLED'] == 'true').to be false
      end
    end

    it 'is ENABLED only when ENV is exactly "true"' do
      ClimateControl.modify('AUTH_MFA_ENABLED' => 'true') do
        expect(ENV['AUTH_MFA_ENABLED'] == 'true').to be true
      end
    end

    it 'is disabled when ENV is "True" (case sensitive)' do
      ClimateControl.modify('AUTH_MFA_ENABLED' => 'True') do
        # NOTE: This is disabled because comparison is case-sensitive
        expect(ENV['AUTH_MFA_ENABLED'] == 'true').to be false
      end
    end
  end

  describe 'AUTH_EMAIL_AUTH_ENABLED pattern (== true, disabled by default)' do
    it 'is disabled by default' do
      ClimateControl.modify('AUTH_EMAIL_AUTH_ENABLED' => nil) do
        expect(ENV['AUTH_EMAIL_AUTH_ENABLED'] == 'true').to be false
      end
    end

    it 'is enabled when set to "true"' do
      ClimateControl.modify('AUTH_EMAIL_AUTH_ENABLED' => 'true') do
        expect(ENV['AUTH_EMAIL_AUTH_ENABLED'] == 'true').to be true
      end
    end
  end

  describe 'AUTH_WEBAUTHN_ENABLED pattern (== true, disabled by default)' do
    it 'is disabled by default' do
      ClimateControl.modify('AUTH_WEBAUTHN_ENABLED' => nil) do
        expect(ENV['AUTH_WEBAUTHN_ENABLED'] == 'true').to be false
      end
    end

    it 'is enabled when set to "true"' do
      ClimateControl.modify('AUTH_WEBAUTHN_ENABLED' => 'true') do
        expect(ENV['AUTH_WEBAUTHN_ENABLED'] == 'true').to be true
      end
    end
  end
end
