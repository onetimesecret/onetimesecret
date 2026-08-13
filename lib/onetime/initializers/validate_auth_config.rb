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

      # The env flags the shipped template (etc/defaults/auth.defaults.yaml)
      # renders full.restrict_to from. Mutually exclusive by construction —
      # restrict_to names exactly ONE method — so more than one is a
      # contradiction, not a list. See #validate_restrict_to_flags!.
      RESTRICT_TO_ENV_FLAGS = {
        'AUTH_PASSWORD_ONLY' => 'password',
        'AUTH_EMAIL_AUTH_ONLY' => 'email_auth',
        'AUTH_WEBAUTHN_ONLY' => 'webauthn',
        'AUTH_SSO_ONLY' => 'sso',
      }.freeze

      def execute(_context)
        validate_present!
        # Fatal when more than one AUTH_*_ONLY flag is set (ADR-024 A9,
        # #4139). Runs BEFORE the rendered value is inspected: conflicting
        # flags render as a blank restrict_to, so by the time the config is
        # parsed the contradiction is gone and validate_restrict_to! below has
        # nothing left to complain about.
        validate_restrict_to_flags!
        # Fatal when full.restrict_to names an unavailable method (ADR-024 A3,
        # #4140). Fail loud at deploy time rather than silently widening the
        # sign-in page to every enabled method.
        Onetime.auth_config.validate_restrict_to!
      end

      # Boot-time validation of the AUTH_*_ONLY env flags (ADR-024 A9, #4139).
      #
      # The template renders full.restrict_to from four mutually exclusive
      # flags and emits NOTHING when more than one is true — so an operator
      # who sets AUTH_SSO_ONLY=true and AUTH_PASSWORD_ONLY=true gets no
      # restriction and no signal. AuthConfig cannot see this: it only ever
      # receives the rendered blank, which every reader on it correctly
      # interprets as "nothing restricted". The contradiction only exists in
      # the process environment, which is why the check lives here — this
      # initializer is already the boot-time enforcement point, and the ENV is
      # boot input rather than parsed-config state.
      #
      # Same defect class as #4140 one layer up, and it fails the same way:
      # refuse to boot, naming every flag the operator set, so the fix is
      # obvious from the deploy log. Zero or one flag is untouched.
      #
      # Full mode only, mirroring AuthConfig#validate_restrict_to!:
      # restrict_to has no meaning in simple mode, so inert flags there must
      # not take a simple-mode install down.
      #
      # @raise [Onetime::ConfigError] when more than one flag is true
      # @return [Array<String>] the flags set (0 or 1) when boot may proceed
      def validate_restrict_to_flags!
        return [] unless Onetime.auth_config.full_enabled?

        set_flags = RESTRICT_TO_ENV_FLAGS.keys.select { |flag| ENV[flag] == 'true' }
        return set_flags if set_flags.length <= 1

        raise Onetime::ConfigError, restrict_to_flags_error_message(set_flags)
      end

      private

      # Operator-facing fatal message. Names every flag that is set — the
      # whole point is that the deploy log identifies the contradiction
      # without a config archaeology session.
      def restrict_to_flags_error_message(set_flags)
        listed = set_flags.map { |flag| "  - #{flag}=true (restrict_to: #{RESTRICT_TO_ENV_FLAGS[flag]})" }
        <<~MSG.strip
          Conflicting authentication restrictions: #{set_flags.length} AUTH_*_ONLY flags
          are set, but sign-in can be restricted to only ONE method.

          #{listed.join("\n")}

          Refusing to boot: conflicting flags render no restriction at all, which
          would silently show every enabled sign-in method — re-exposing exactly the
          methods these settings restrict away.

          To fix this issue:
          1. Set exactly one of: #{RESTRICT_TO_ENV_FLAGS.keys.join(', ')}, or
          2. Unset all of them to show all enabled authentication methods.
        MSG
      end

      def validate_present!
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
