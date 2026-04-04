# apps/api/domains/logic/incoming_config/put_incoming_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/incoming_config'
require_relative 'base'
require_relative 'serializers'

module DomainsAPI
  module Logic
    module IncomingConfig
      # Create/Replace Domain Incoming Configuration
      #
      # @api Creates or replaces the incoming secrets configuration for a custom domain.
      #   Sets the full list of recipients, replacing any existing configuration.
      #   Requires the requesting user to be an organization owner with incoming_secrets.
      #
      # Request body:
      # - enabled: Boolean (optional, default false)
      # - recipients: Array of {email, name} objects
      #
      # Response includes:
      # - domain_id: The domain identifier
      # - enabled: Whether incoming secrets is active
      # - recipients: Array of {email, name}
      # - max_recipients: Maximum allowed recipients (20)
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class PutIncomingConfig < Base
        include Serializers

        attr_reader :incoming_config

        def process_params
          @domain_id           = sanitize_identifier(params['extid'])
          @enabled             = parse_boolean(params['enabled'])
          @recipients_provided = params.key?('recipients')
          @recipients          = parse_recipients(params['recipients'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_incoming!(@domain_id)

          # Validate recipients
          max = Onetime::CustomDomain::IncomingConfig::MAX_RECIPIENTS
          if @recipients.size > max
            raise_form_error("Maximum #{max} recipients allowed", field: :recipients, error_type: :invalid)
          end

          # Validate recipient emails
          @recipients.each do |r|
            unless r[:email].match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
              raise_form_error("Invalid email format: #{r[:email]}", field: :recipients, error_type: :invalid)
            end
          end

          # Check for duplicate emails
          emails = @recipients.map { |r| r[:email] }
          if emails.uniq.size != emails.size
            raise_form_error('Duplicate recipient emails not allowed', field: :recipients, error_type: :invalid)
          end
        end

        def process
          OT.ld "[PutIncomingConfig] Setting incoming config for domain #{@domain_id} by user #{cust.extid}"

          # Find or create config
          @incoming_config = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@custom_domain.identifier)

          if @incoming_config
            # Update existing
            @incoming_config.enabled = @enabled.to_s
            # Only update recipients if explicitly provided in the request.
            # This allows toggling enabled state without wiping recipients.
            if @recipients_provided
              @incoming_config.recipients = @recipients
            end
            @incoming_config.updated = Familia.now.to_i
            @incoming_config.save
          else
            # Create new
            @incoming_config = Onetime::CustomDomain::IncomingConfig.create!(
              domain_id: @custom_domain.identifier,
              enabled: @enabled,
              recipients: @recipients,
            )
          end

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_incoming_config_admin(@incoming_config),
          }
        end
      end
    end
  end
end
