
require 'public_suffix'

require_relative 'base'
require_relative '../cluster'

module Onetime::Logic
  module Domains

    class UpdateSubdomain < OT::Logic::Base
      attr_reader :subdomain, :cname, :properties
      def process_params
        @cname = params[:cname].to_s.downcase.strip.slice(0,30)
        @properties = {
          :company => params[:company].to_s.strip.slice(0,120),
          :homepage => params[:homepage].to_s.strip.slice(0,120),
          :contact => params[:contact].to_s.strip.slice(0,60),
          :email => params[:email].to_s.strip.slice(0,120),
          :logo_uri => params[:logo_uri].to_s.strip.slice(0,120),
          :primary_color => params[:cp].to_s.strip.slice(0,30),
          :secondary_color => params[:cs].to_s.strip.slice(0,30),
          :border_color => params[:cb].to_s.strip.slice(0,30)
        }
      end

      def raise_concerns
        limit_action :update_branding
        if %w{www yourcompany mycompany admin ots secure secrets onetime onetimesecret}.member?(@cname)
          raise_form_error "That CNAME is not available"
        elsif ! @cname.empty?
          @subdomain = OT::Subdomain.load_by_cname(@cname)
          raise_form_error "That CNAME is not available" if subdomain && !subdomain.owner?(cust.custid)
        end
        if ! properties[:logo_uri].empty?
          begin
            URI.parse properties[:logo_uri]
          rescue StandardError => ex
            raise_form_error "Check the logo URI"
          end
        end
      end

      def process
        @subdomain ||= OT::Subdomain.create cust.custid, @cname
        if cname.empty?
          sess.set_error_message "Nothing changed"
        else
          OT::Subdomain.rem cust['cname']
          subdomain.update_cname cname
          subdomain.update_fields properties
          cust.update_fields :cname => subdomain.cname
          OT::Subdomain.add cname, cust.custid
          sess.set_info_message "Branding updated"
        end
        sess.set_form_fields form_fields # for tabindex
      end

      def success_data
        { custid: @cust.custid }
      end
    end

    class AddDomain < OT::Logic::Base
      attr_reader :greenlighted, :custom_domain

      def process_params
        OT.ld "[AddDomain] Parsing #{params[:domain]}"
         # PublicSuffix does its own normalizing so we don't need to do any here
         @domain_input = params[:domain].to_s
      end

      def raise_concerns

        OT.ld "[AddDomain] Raising any concerns about #{@domain_input}"
        # TODO: Consider returning all applicable errors (plural) at once
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :add_domain

        # Only store a valid, parsed input value to @domain
        @parsed_domain = OT::CustomDomain.parse(@domain_input, @cust) # raises OT::Problem
        @display_domain = @parsed_domain[:display_domain]


        # Don't need to do a bunch of validation checks here. If the input value
        # passes as valid, it's valid. If another account has verified the same
        # domain, that's fine. Both accounts can generate secret links for that
        # domain, and the links will be valid for both accounts.
        #
        #   e.g. `OT::CustomDomain.exists?(@domain)`

      end

      def process
        @greenlighted = true
        OT.ld "[AddDomain] Processing #{@display_domain}"
        @custom_domain = OT::CustomDomain.create(@display_domain, @cust.custid)

        # Create the approximated vhost for this domain. Approximated provides a
        # custom domain as a service API. If no API key is set, then this will
        # simply log a message and return.
        create_vhost
      end

      def create_vhost
        api_key = OT::Cluster::Features.api_key

        if api_key.to_s.empty?
          return OT.info "[AddDomain.create_vhost] Approximated API key not set"
        end

        res = OT::Cluster::Approximated.create_vhost(api_key, @display_domain, 'staging.onetimesecret.com', '443')
        payload = res.parsed_response
        OT.info "[AddDomain.create_vhost] %s" % payload
        custom_domain[:vhost] = payload['data'].to_json
        custom_domain[:updated] = OT.now.to_i

      rescue HTTParty::ResponseError => e
        OT.le "[AddDomain.create_vhost error] %s %s %s"  % [@cust.custid, @display_domain, e]
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: OT::Cluster::Features.cluster_safe_dump
          }
        }
      end
    end

    class RemoveDomain < OT::Logic::Base
      attr_reader :greenlighted, :domain_input, :display_domain
      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :remove_domain

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust)
        raise_form_error "Domain not found" unless @custom_domain
      end

      def process
        OT.ld "[RemoveDomain] Processing #{domain_input} for #{@custom_domain.identifier}"
        @greenlighted = true
        @display_domain = @custom_domain[:display_domain]

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

    class ListDomains < OT::Logic::Base
      attr_reader :custom_domains

      def raise_concerns
        limit_action :list_domains
      end

      def process
        OT.ld "[ListDomains] Processing #{@cust.custom_domains_list.length}"
        @custom_domains = @cust.custom_domains.map { |cd| cd.safe_dump }
      end

      def success_data
        {
          custid: @cust.custid,
          records: @custom_domains,
          count: @custom_domains.length,
          details: {
            cluster: OT::Cluster::Features.cluster_safe_dump
          }
        }
      end
    end

    class GetDomain < OT::Logic::Base

      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :get_domain

        # Getting the domain record based on `req.params[:domain]` (which is
        # the display_domain). That way we need to combine with the custid
        # in order to find it. It's a way of proving ownership. Vs passing the
        # domainid in the URL path which gives up the goods.
        @custom_domain = OT::CustomDomain.load(@domain_input, @cust)

        raise_form_error "Domain not found" unless @custom_domain
      end

      def process
        OT.ld "[GetDomain] Processing #{@custom_domain[:display_domain]}"
        @greenlighted = true
        @display_domain = @custom_domain[:display_domain]
      end

      def success_data
        {
          custid: @cust.custid,
          record: custom_domain.safe_dump,
          details: {
            cluster: OT::Cluster::Features.cluster_safe_dump
          }
        }
      end
    end

    class VerifyDomain < GetDomain

      def raise_concerns
        # Run this limiter before calling super which in turn runs
        # the get_domain limiter since verify is a more restrictive. No
        # sense running the get logic more than we need to.
        limit_action :verify_domain

        super
      end

      def process
        super

        refresh_vhost
      end

      def refresh_vhost
        api_key = OT::Cluster::Features.api_key
        if api_key.to_s.empty?
          return OT.info "[VerifyDomain.refresh_vhost] Approximated API key not set"
        end
        res = OT::Cluster::Approximated.get_vhost_by_incoming_address(api_key, display_domain)
        payload = res.parsed_response
        OT.info "[VerifyDomain.refresh_vhost] %s" % payload
        OT.ld ""
        custom_domain[:vhost] = payload['data'].to_json
        custom_domain[:updated] = OT.now.to_i
      end
    end
  end
end
