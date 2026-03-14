# apps/api/domains/logic/domains/get_domain_recipients.rb
#
# frozen_string_literal: true

require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Returns the configured incoming secret recipients for a custom domain.
    #
    # Recipients are returned hashed (no email addresses exposed).
    # Requires the incoming_secrets entitlement.
    #
    # @example Response
    #   {
    #     user_id: "abc123",
    #     record: {
    #       recipients: [
    #         { hash: "sha256...", name: "Support Team" }
    #       ],
    #       memo_max_length: 50,
    #       default_ttl: 604800
    #     }
    #   }
    #
    class GetDomainRecipients < DomainsAPI::Logic::Base
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
        success_data
      end

      def success_data
        config = @custom_domain.incoming_secrets_config
        site_secret = OT.conf.dig('site', 'secret')
        {
          user_id: @cust.objid,
          record: {
            recipients: config.public_incoming_recipients(site_secret),
            memo_max_length: config.memo_max_length,
            default_ttl: config.default_ttl,
          },
        }
      end

    end
  end
end
