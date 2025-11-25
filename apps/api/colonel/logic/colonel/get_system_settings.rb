# apps/api/colonel/logic/colonel/get_system_settings.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetSystemSettings < ColonelAPI::Logic::Base
        attr_reader :config_sections

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @config_sections = {}

          # Safe config (always included)
          @config_sections[:interface] = Onetime.conf[:site] || {}
          @config_sections[:secret_options] = {
            default_ttl: Onetime.conf[:default][:ttl],
            max_ttl: Onetime.conf[:default][:max_ttl],
            default_size: Onetime.conf[:default][:size],
          }
          @config_sections[:limits] = Onetime.conf[:limits] || {}
          @config_sections[:mail] = Onetime.conf[:emailer] || {}
          @config_sections[:diagnostics] = {
            redis_uri: Onetime.conf[:redis]&.[](:uri)&.gsub(/:[^:@]*@/, ':****@'), # Mask password
            entropy_enabled: Onetime.conf[:entropy]&.[](:enabled),
            colonel_enabled: Onetime.conf[:colonel]&.[](:enabled),
          }

          # Auth config (if advanced auth is enabled)
          if Onetime.conf.key?(:authentication)
            @config_sections[:authentication] = Onetime.conf[:authentication] || {}
          end

          # Logging config
          if Onetime.conf.key?(:logging)
            @config_sections[:logging] = Onetime.conf[:logging] || {}
          end

          # Billing config (if enabled)
          if Onetime.conf.key?(:billing) && Onetime.conf[:billing]&.[](:enabled)
            @config_sections[:billing] = Onetime.conf[:billing] || {}
          end

          success_data
        end

        def success_data
          {
            record: {},
            details: config_sections,
          }
        end
      end
    end
  end
end
