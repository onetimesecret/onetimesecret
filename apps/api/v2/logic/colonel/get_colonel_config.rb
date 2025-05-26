# apps/api/v2/logic/colonel/get_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetColonelConfig < V2::Logic::Base
        attr_reader :config, :interface, :secret_options, :mail, :limits,
          :diagnostics

        def process_params
          @interface = OT.conf.dig(:site, :interface)
          @secret_options = OT.conf.dig(:site, :secret_options)
          @mail = OT.conf.fetch(:mail, {})
          @limits = OT.conf.fetch(:limits, {})
          @diagnostics = OT.conf.fetch(:diagnostics, {})
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
        end

        def success_data
          {
            record: {},
            details: {
              interface: interface,
              secret_options: secret_options,
              mail: mail,
              limits: limits,
              diagnostics: diagnostics,
            }
          }
        end
      end
    end
  end
end
