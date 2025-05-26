# apps/api/v2/logic/colonel/update_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class UpdateColonelConfig < V2::Logic::Base
        @safe_fields = [:interface, :secret_options, :mail, :limits,
                        :diagnostics]

        attr_reader :config, :interface, :secret_options, :mail, :limits,
                    :experimental

        def process_params
          OT.ld "[UpdateColonelConfig#process_params] params: #{params.inspect}"
          # Accept config either directly or wrapped in a :config key
          @config = params.key?(:config) ? params[:config] : params

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
          raise_form_error "No valid configuration sections found" if present_fields.empty?

          # Log unsupported fields but don't error
          unsupported_fields = config_keys - self.class.safe_fields
          OT.ld "[UpdateColonelConfig#raise_concerns] Ignoring unsupported fields: #{unsupported_fields.join(', ')}" unless unsupported_fields.empty?
        end

        def process
          OT.ld "[UpdateColonelConfig#process] Updating configuration"

          begin
            # Update site configuration
            OT.conf[:site] ||= {}
            OT.conf[:site][:interface] = interface if interface
            OT.conf[:site][:secret_options] = secret_options if secret_options

            # Update other top-level configurations with deep merge to preserve existing settings
            OT.conf[:mail] = OT.conf.fetch(:mail, {}).merge(mail) if mail
            OT.conf[:limits] = OT.conf.fetch(:limits, {}).merge(limits) if limits
            OT.conf[:diagnostics] = OT.conf.fetch(:diagnostics, {}).merge(diagnostics) if diagnostics
            OT.conf[:development] = OT.conf.fetch(:development, {}).merge(development) if development
            OT.conf[:experimental] = OT.conf.fetch(:experimental, {}).merge(experimental) if experimental

            # Save updated configuration to Redis or other persistent storage
            OT.save_conf

            OT.ld "[UpdateColonelConfig#process] Configuration updated successfully"
          rescue => ex
            OT.ld "[UpdateColonelConfig#process] Error updating configuration: #{ex.message}"
            OT.ld "[UpdateColonelConfig#process] #{ex.backtrace.join("\n")}" if ex.backtrace
            raise_form_error "Failed to save configuration: #{ex.message}"
          end
        end

        def success_data
          OT.ld "[UpdateColonelConfig#success_data] Returning updated configuration"

          # Create a response that matches the GetColonelConfig format
          response = {
            record: {},
            details: {}
          }

          # Only include sections that were provided in the request
          response[:details][:interface] = interface if interface
          response[:details][:secret_options] = secret_options if secret_options
          response[:details][:mail] = mail if mail
          response[:details][:limits] = limits if limits
          response[:details][:diagnostics] = diagnostics if diagnostics
          response[:details][:development] = development if development
          response[:details][:experimental] = experimental if experimental

          response
        end

        class << self
          attr_reader :safe_fields
        end
      end
    end
  end
end
