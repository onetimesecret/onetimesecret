# apps/api/v2/logic/colonel/update_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class UpdateColonelConfig < V2::Logic::Base
        @safe_fields = [:interface, :secret_options, :mail, :limits,
                        :diagnostics]

        attr_reader :config, :interface, :secret_options, :mail, :limits,
                    :diagnostics, :greenlighted, :record

        def process_params
          OT.ld "[UpdateColonelConfig#process_params] params: #{params.inspect}"
          # Accept config either directly or wrapped in a :config key
          @config = params[:config]

          # Extract configuration sections
          @interface = config[:interface]
          @secret_options = config[:secret_options]
          @mail = config[:mail]
          @limits = config[:limits]
          @diagnostics = config[:diagnostics]
          # require 'pry-byebug'; binding.pry;
          # Log which configuration sections were extracted
          config_sections = {
            interface: interface,
            secret_options: secret_options,
            mail: mail,
            limits: limits,
            diagnostics: diagnostics,
          }

          OT.ld "[UpdateColonelConfig#process_params] Extracted config sections: " +
                config_sections.map { |name, value| "#{name}=#{!!value}" }.join(", ")
        end

        def raise_concerns
          limit_action :update_colonel_config
          raise_form_error "`config` was empty" if config.empty?

          # Normalize keys to symbols for comparison
          config_keys = config.keys.map { |k| k.respond_to?(:to_sym) ? k.to_sym : k }

          # Ensure at least one valid field is present (not requiring all sections)
          present_fields = self.class.safe_fields & config_keys

          OT.ld "[UpdateColonelConfig#raise_concerns] Present fields: #{present_fields.join(', ')}"
          raise_form_error "No valid configuration sections found" if present_fields.empty?

          # Log unsupported fields but don't error
          unsupported_fields = config_keys - self.class.safe_fields
          OT.ld "[UpdateColonelConfig#raise_concerns] Ignoring unsupported fields: #{unsupported_fields.join(', ')}" unless unsupported_fields.empty?
        end

        def process
          OT.ld "[UpdateColonelConfig#process] Updating configuration"

          OT.li "[UpdateColonelConfig#process] Interface: #{interface.inspect}" if interface
          OT.li "[UpdateColonelConfig#process] Secret Options: #{secret_options.inspect}" if secret_options
          OT.li "[UpdateColonelConfig#process] Mail: #{mail.inspect}" if mail
          OT.li "[UpdateColonelConfig#process] Limits: #{limits.inspect}" if limits
          OT.li "[UpdateColonelConfig#process] Diagnostics: #{diagnostics.inspect}" if diagnostics


          # Only include sections that were provided in the request
          @updated_fields = {}
          @updated_fields[:interface] = interface if interface
          @updated_fields[:secret_options] = secret_options if secret_options
          @updated_fields[:mail] = mail if mail
          @updated_fields[:limits] = limits if limits
          @updated_fields[:diagnostics] = diagnostics if diagnostics

          current_config = ColonelConfig.current || ColonelConfig.new
          filtered_fields = current_config.filtered
          merged_config = OT::Config.deep_merge(filtered_fields, @updated_fields)

          # Create a new ColonelConfig object with the updated values
          @record = ColonelConfig.create(**merged_config)

          @greenlighted = true
        end

        def success_data
          OT.ld "[UpdateColonelConfig#success_data] Returning updated configuration"

          # Create a response that matches the GetColonelConfig format
          response = {
            record: @record,
            details: @updated_fields,
          }

          response
        end

        class << self
          attr_reader :safe_fields
        end
      end
    end
  end
end
