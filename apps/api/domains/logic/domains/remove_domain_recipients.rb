# apps/api/domains/logic/domains/remove_domain_recipients.rb
#
# frozen_string_literal: true

require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Removes all incoming secret recipients from a custom domain.
    #
    # This effectively disables incoming secrets for the domain.
    # Requires the incoming_secrets entitlement.
    #
    # @example Request
    #   DELETE /api/domains/:extid/recipients
    #
    class RemoveDomainRecipients < DomainsAPI::Logic::Base
      attr_reader :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        require_entitlement!('incoming_secrets')

        raise_form_error 'Please provide a domain ID' if @extid.empty?

        unless valid_extid?(@extid)
          raise_form_error 'Invalid domain identifier format'
        end

        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)

        raise_form_error 'Domain not found' unless @custom_domain&.exists?

        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end
      end

      def process
        # Clear all recipients
        config = @custom_domain.incoming_secrets_config
        config.clear_incoming_recipients

        # Persist to Redis
        @custom_domain.update_incoming_secrets_config(config)

        OT.info "[RemoveDomainRecipients] Cleared recipients for domain #{@extid}"

        success_data
      end

      def success_data
        {
          user_id: @cust.objid,
          record: {
            recipients: [],
            memo_max_length: Onetime::CustomDomain::IncomingSecretsConfig::DEFAULTS[:memo_max_length],
            default_ttl: Onetime::CustomDomain::IncomingSecretsConfig::DEFAULTS[:default_ttl],
          },
        }
      end

      private

      def valid_extid?(extid)
        extid.match?(/\A[a-z0-9]+\z/)
      end
    end
  end
end
