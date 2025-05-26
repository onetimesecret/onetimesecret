# apps/api/v2/logic/colonel/get_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class UpdateColonelConfig < V2::Logic::Base
        @safe_fields = [:interface, :secret_options, :mail, :limits,
                        :experimental, :diagnostics]

        attr_reader :config, :interface, :secret_options, :mail, :limits,
                    :experimental, :diagnostics

        def process_params
          OT.ld "[UpdateColonelConfig#process_params] params: #{params.inspect}"
          @config = params[:config] || {}

        end

        def raise_concerns
          limit_action :update_colonel_config
          raise_form_error "`config` was empty" unless config.size > 0

          self.class.safe_fields.each do |field|
            raise_form_error "Invalid field: #{field}" unless config.key?(field)
          end
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
              experimental: experimental,
            }
          }
        end

        class << self
          attr_reader :safe_fields
        end
      end
    end
  end
end
