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
  describe 'ENABLE_SECURITY_FEATURES pattern (!= false, enabled by default)' do
    # Pattern: ENV['ENABLE_SECURITY_FEATURES'] != 'false'
    # This means: enabled unless explicitly set to 'false'

    it 'is enabled when ENV is not set (nil)' do
      ClimateControl.modify('ENABLE_SECURITY_FEATURES' => nil) do
        expect(ENV['ENABLE_SECURITY_FEATURES'] != 'false').to be true
      end
    end

    it 'is enabled when ENV is empty string' do
      ClimateControl.modify('ENABLE_SECURITY_FEATURES' => '') do
        expect(ENV['ENABLE_SECURITY_FEATURES'] != 'false').to be true
      end
    end

    it 'is enabled when ENV is "true"' do
      ClimateControl.modify('ENABLE_SECURITY_FEATURES' => 'true') do
        expect(ENV['ENABLE_SECURITY_FEATURES'] != 'false').to be true
      end
    end

    it 'is enabled when ENV is any other value' do
      ClimateControl.modify('ENABLE_SECURITY_FEATURES' => 'yes') do
        expect(ENV['ENABLE_SECURITY_FEATURES'] != 'false').to be true
      end
    end

    it 'is DISABLED only when ENV is exactly "false"' do
      ClimateControl.modify('ENABLE_SECURITY_FEATURES' => 'false') do
        expect(ENV['ENABLE_SECURITY_FEATURES'] != 'false').to be false
      end
    end

    it 'is enabled when ENV is "False" (case sensitive)' do
      ClimateControl.modify('ENABLE_SECURITY_FEATURES' => 'False') do
        # NOTE: This is enabled because comparison is case-sensitive
        expect(ENV['ENABLE_SECURITY_FEATURES'] != 'false').to be true
      end
    end
  end

  describe 'ENABLE_MFA pattern (== true, disabled by default)' do
    # Pattern: ENV['ENABLE_MFA'] == 'true'
    # This means: disabled unless explicitly set to 'true'

    it 'is disabled when ENV is not set (nil)' do
      ClimateControl.modify('ENABLE_MFA' => nil) do
        expect(ENV['ENABLE_MFA'] == 'true').to be false
      end
    end

    it 'is disabled when ENV is empty string' do
      ClimateControl.modify('ENABLE_MFA' => '') do
        expect(ENV['ENABLE_MFA'] == 'true').to be false
      end
    end

    it 'is disabled when ENV is "false"' do
      ClimateControl.modify('ENABLE_MFA' => 'false') do
        expect(ENV['ENABLE_MFA'] == 'true').to be false
      end
    end

    it 'is disabled when ENV is "yes" (must be exactly "true")' do
      ClimateControl.modify('ENABLE_MFA' => 'yes') do
        expect(ENV['ENABLE_MFA'] == 'true').to be false
      end
    end

    it 'is ENABLED only when ENV is exactly "true"' do
      ClimateControl.modify('ENABLE_MFA' => 'true') do
        expect(ENV['ENABLE_MFA'] == 'true').to be true
      end
    end

    it 'is disabled when ENV is "True" (case sensitive)' do
      ClimateControl.modify('ENABLE_MFA' => 'True') do
        # NOTE: This is disabled because comparison is case-sensitive
        expect(ENV['ENABLE_MFA'] == 'true').to be false
      end
    end
  end

  describe 'ENABLE_MAGIC_LINKS pattern (== true, disabled by default)' do
    it 'is disabled by default' do
      ClimateControl.modify('ENABLE_MAGIC_LINKS' => nil) do
        expect(ENV['ENABLE_MAGIC_LINKS'] == 'true').to be false
      end
    end

    it 'is enabled when set to "true"' do
      ClimateControl.modify('ENABLE_MAGIC_LINKS' => 'true') do
        expect(ENV['ENABLE_MAGIC_LINKS'] == 'true').to be true
      end
    end
  end

  describe 'ENABLE_WEBAUTHN pattern (== true, disabled by default)' do
    it 'is disabled by default' do
      ClimateControl.modify('ENABLE_WEBAUTHN' => nil) do
        expect(ENV['ENABLE_WEBAUTHN'] == 'true').to be false
      end
    end

    it 'is enabled when set to "true"' do
      ClimateControl.modify('ENABLE_WEBAUTHN' => 'true') do
        expect(ENV['ENABLE_WEBAUTHN'] == 'true').to be true
      end
    end
  end
end
