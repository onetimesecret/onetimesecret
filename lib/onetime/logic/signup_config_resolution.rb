# lib/onetime/logic/signup_config_resolution.rb
#
# frozen_string_literal: true

module Onetime
  module Logic
    # Shared domain-level SignupConfig lookup and autoverify resolution.
    #
    # Includers must provide:
    #   - #signup_config_display_domain  → String or nil
    #   - #signup_config_auth_setting(key) → the value of auth.{key} from site config
    module SignupConfigResolution
      private

      def resolve_autoverify
        config = domain_signup_config
        return config.autoverify? if config&.enabled?

        signup_config_auth_setting('autoverify').to_s == 'true'
      end

      def domain_signup_config
        dd = signup_config_display_domain
        return unless dd

        custom_domain = Onetime::CustomDomain.load_by_display_domain(dd)
        return unless custom_domain

        Onetime::CustomDomain::SignupConfig.find_by_domain_id(custom_domain.identifier)
      end
    end
  end
end
