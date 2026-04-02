# apps/api/domains/logic/incoming_config/get_incoming_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/incoming_config'
require_relative 'base'
require_relative 'serializers'

module DomainsAPI
  module Logic
    module IncomingConfig
      # Get Domain Incoming Configuration
      #
      # @api Retrieves the incoming secrets configuration for a custom domain.
      #   Returns the config with recipient names and hashes (emails hidden).
      #   Requires the requesting user to be an organization owner with incoming_secrets.
      #
      # Response includes:
      # - domain_id: The domain identifier
      # - enabled: Whether incoming secrets is active
      # - recipients: Array of {hash, name} (emails are hashed)
      # - max_recipients: Maximum allowed recipients (20)
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class GetIncomingConfig < Base
        include Serializers

        attr_reader :incoming_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_incoming!(@domain_id)

          # Load incoming config (may not exist yet)
          @incoming_config = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@custom_domain.identifier)
        end

        def process
          OT.ld "[GetIncomingConfig] Getting incoming config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          if @incoming_config
            {
              user_id: cust.extid,
              record: serialize_incoming_config_admin(@incoming_config),
            }
          else
            # Return empty/unconfigured state
            {
              user_id: cust.extid,
              record: {
                domain_id: @custom_domain.identifier,
                enabled: false,
                recipients: [],
                max_recipients: Onetime::CustomDomain::IncomingConfig::MAX_RECIPIENTS,
                created_at: nil,
                updated_at: nil,
              },
            }
          end
        end
      end
    end
  end
end
