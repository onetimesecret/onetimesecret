# apps/api/domains/logic/domains/remove_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class RemoveDomain < DomainsAPI::Logic::Base
      attr_reader :greenlighted, :extid, :display_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)
        raise_form_error 'Domain not found' unless @custom_domain

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end
      end

      def process
        OT.ld "[RemoveDomain] Processing #{@extid} (#{@custom_domain.display_domain})"
        @greenlighted   = true
        @display_domain = @custom_domain.display_domain

        # Delete from external SSL provider via strategy
        delete_vhost

        # Destroy method operates inside a multi block that deletes the domain
        # record, removes it from customer's domain list, and global list so
        # it's all or nothing. It does not delete the external approximated
        # vhost record.
        @custom_domain.destroy!

        # Clear the session's domain context if it matches the removed domain.
        # Under BasicAuth sess is {}, so sess['domain_context'] is nil and
        # this branch is safely skipped — no session state to clean up.
        if sess && sess['domain_context'] == @display_domain
          sess['domain_context'] = nil
        end

        success_data
      end

      # Deletes vhost from external provider using the configured strategy.
      # For Approximated strategy, this calls the API. For other strategies,
      # this is a no-op.
      #
      def delete_vhost
        strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
        result   = strategy.delete_vhost(@custom_domain)

        OT.info "[RemoveDomain.delete_vhost] #{@display_domain} -> #{result[:message]}"
      rescue HTTParty::ResponseError, Timeout::Error, Errno::ECONNREFUSED => ex
        OT.le "[RemoveDomain.delete_vhost error] #{@cust.extid} #{@display_domain} #{ex}"
        # Continue with domain removal even if vhost deletion fails
      end

      def success_data
        {
          user_id: @cust.objid,
          record: {},
          message: "Removed #{display_domain}",
        }
      end
    end
  end
end
