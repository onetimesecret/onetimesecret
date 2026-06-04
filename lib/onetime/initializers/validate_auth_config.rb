# lib/onetime/initializers/validate_auth_config.rb
#
# frozen_string_literal: true

require_relative '../auth_config'

module Onetime
  module Initializers
    # Validates that etc/auth.yaml is present and loaded.
    #
    # AuthConfig itself tolerates a missing file (sets config to nil) so
    # that require-time plugin discovery doesn't crash. This initializer
    # is the boot-time enforcement point: any process that calls
    # OT.boot! (web server, worker, scheduler, or CLI commands that
    # inherit from Command) will fail fast with a clear message.
    #
    # Commands that inherit from DelayBootCommand never call OT.boot!,
    # so this initializer never runs for them — no skip logic needed.
    #
    class ValidateAuthConfig < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:auth_config_validated]

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
