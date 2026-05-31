# lib/onetime/initializers/validate_auth_config.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # Validates that etc/auth.yaml is present and loaded for process modes
    # that require authentication (backend, worker, scheduler).
    #
    # CLI commands skip this check — read-only tooling like
    # `billing catalog generate-docs` should not require a fully-provisioned
    # environment. AuthConfig itself tolerates a missing file (sets config
    # to nil), so this initializer is the enforcement point for modes that
    # genuinely need auth.
    #
    class ValidateAuthConfig < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:auth_config_validated]

      def should_skip?
        OT.execution_mode == :cli
      end

      def execute(_context)
        return if Onetime.auth_config.configured?

        raise Onetime::ConfigError, <<~MSG.strip
          Authentication configuration required for #{OT.execution_mode} mode.
          File not found: #{Onetime.auth_config.path}

          To fix this issue:
          1. Copy etc/defaults/auth.defaults.yaml to etc/auth.yaml
          2. Verify YAML syntax is valid
          3. Check file permissions
        MSG
      end
    end
  end
end
