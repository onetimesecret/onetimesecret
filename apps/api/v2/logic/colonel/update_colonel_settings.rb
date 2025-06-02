# apps/api/v2/logic/colonel/update_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class UpdateColonelSettings < V2::Logic::Base
        @safe_fields = [:interface, :secret_options, :mail, :limits,
                        :diagnostics]

        attr_reader :config, :interface, :secret_options, :mail, :limits,
                    :diagnostics, :greenlighted, :record

        def process_params
          OT.ld "[UpdateColonelSettings#process_params] params: #{params.inspect}"
          # Accept config either directly or wrapped in a :config key
          @config = params[:config]

          # Extract configuration sections
          @interface = config[:interface]
          @secret_options = config[:secret_options]
          @mail = config[:mail]
          @limits = config[:limits]
          @diagnostics = config[:diagnostics]

          # Log which configuration sections were extracted
          config_sections = {
            interface: interface,
            secret_options: secret_options,
            mail: mail,
            limits: limits,
            diagnostics: diagnostics,
          }

          OT.ld "[UpdateColonelSettings#process_params] Extracted config sections: " +
                config_sections.map { |name, value| "#{name}=#{!!value}" }.join(", ")
        end

        def raise_concerns
          limit_action :update_colonel_config
          raise_form_error "`config` was empty" if config.empty?

          # Normalize keys to symbols for comparison
          config_keys = config.keys.map { |k| k.respond_to?(:to_sym) ? k.to_sym : k }

          # Ensure at least one valid field is present (not requiring all sections)
          present_fields = self.class.safe_fields & config_keys

          OT.ld "[UpdateColonelSettings#raise_concerns] Present fields: #{present_fields.join(', ')}"
          raise_form_error "No valid configuration sections found" if present_fields.empty?

          # Log unsupported fields but don't error
          unsupported_fields = config_keys - self.class.safe_fields
          OT.ld "[UpdateColonelSettings#raise_concerns] Ignoring unsupported fields: #{unsupported_fields.join(', ')}" unless unsupported_fields.empty?
        end

        def process
          OT.ld "[UpdateColonelSettings#process] Persisting colonel configuration"

          OT.li "[UpdateColonelSettings#process] Interface: #{interface.inspect}" if interface
          OT.li "[UpdateColonelSettings#process] Secret Options: #{secret_options.inspect}" if secret_options
          OT.li "[UpdateColonelSettings#process] Mail: #{mail.inspect}" if mail
          OT.li "[UpdateColonelSettings#process] Limits: #{limits.inspect}" if limits
          OT.li "[UpdateColonelSettings#process] Diagnostics: #{diagnostics.inspect}" if diagnostics

          begin
            # Build the update fields - only include non-nil values
            update_fields = build_update_fields

            # Create a new ColonelSettings record with the updated values
            @record = ColonelSettings.create(**update_fields)

            @greenlighted = true
            OT.ld "[UpdateColonelSettings#process] Colonel configuration persisted successfully"

          rescue => e
            OT.le "[UpdateColonelSettings#process] Failed to persist colonel configuration: #{e.message}"
            raise_form_error "Failed to update configuration: #{e.message}"
          end
        end

        def success_data
          OT.ld "[UpdateColonelSettings#success_data] Returning updated colonel configuration"

          # Return the record and the sections that were provided
          {
            record: @record&.safe_dump || {},
            details: build_update_fields
          }
        end

        private

        def build_update_fields
          fields = {}
          # Only include sections that were provided and are not nil/empty
          fields[:interface] = interface if interface && !interface.empty?
          fields[:secret_options] = secret_options if secret_options && !secret_options.empty?
          fields[:mail] = mail if mail && !mail.empty?
          fields[:limits] = limits if limits && !limits.empty?
          fields[:diagnostics] = diagnostics if diagnostics && !diagnostics.empty?

          # Add metadata
          fields[:custid] = @cust.custid if @cust
          fields[:created] = Time.now.to_i
          fields[:updated] = Time.now.to_i

          fields
        end

        class << self
          attr_reader :safe_fields
        end
      end
    end
  end
end
