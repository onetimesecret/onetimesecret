require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class RemoveDomain < OT::Logic::Base
      attr_reader :greenlighted, :domain_input, :display_domain
      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :remove_domain

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error "Domain not found" unless @custom_domain
      end

      def process
        OT.ld "[RemoveDomain] Processing #{domain_input} for #{@custom_domain.identifier}"
        @greenlighted = true
        @display_domain = @custom_domain.display_domain

        # TODO: @custom_domain.redis.multi

        @custom_domain.destroy!(@cust)

        # NOTE: Disable deleting the domain from the cluster vhost to
        # avoid issue with two customers adding the same domain and then
        # one removing it. This would cause the domain to be removed for
        # both customers, which would be surprising. Instead, we can
        # just disable the domain for this customer and let them add it
        # again if they want to use it in the future.
        #
        # delete_vhost
      end

      def delete_vhost
        api_key = OT::Cluster::Features.api_key
        if api_key.to_s.empty?
          return OT.info "[RemoveDomain.delete_vhost] Approximated API key not set"
        end
        res = OT::Cluster::Approximated.delete_vhost(api_key, @display_domain)
        payload = res.parsed_response
        OT.info "[RemoveDomain.delete_vhost] %s" % payload
      rescue HTTParty::ResponseError => e
        OT.le "[RemoveDomain.delete_vhost error] %s %s %s"  % [@cust.custid, @display_domain, e]
      end

      def success_data
        {
          custid: @cust.custid,
          record: {},
          message: "Removed #{display_domain}"
        }
      end
    end
  end
end
