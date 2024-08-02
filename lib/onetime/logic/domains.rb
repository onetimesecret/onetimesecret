
require 'public_suffix'

require_relative 'base'

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
          rescue => ex
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

    module ClusterFeatures
      @type = nil
      @api_key = nil
      @cluster_ip = nil
      @cluster_name = nil

      module ClassMethods
        attr_accessor :type, :api_key, :cluster_ip, :cluster_name
      end

      def cluster_safe_dump
        {
          type:  ClusterFeatures.type,
          cluster_ip: ClusterFeatures.cluster_ip,
          cluster_name: ClusterFeatures.cluster_name
        }
      end

      extend ClassMethods
    end

    class AddDomain < OT::Logic::Base
      attr_reader :greenlighted, :custom_domain
      include ClusterFeatures # for cluster_safe_dump

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

        # Only store a valid, parsed input value to @domain
        @parsed_domain = OT::CustomDomain.parse(@domain_input, @cust) # raises OT::Problem
        @display_domain = @parsed_domain[:display_domain]

        limit_action :add_domain

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
        api_key = ClusterFeatures.api_key

        if api_key.to_s.empty?
          return OT.info "[AddDomain.create_vhost] Approximated API key not set"
        end

        res = OT::Utils::Approximated.create_vhost(api_key, @display_domain, 'staging.onetimesecret.com', '443')
        payload = res.parsed_response
        OT.info "[AddDomain.create_vhost] %s" % payload
        @custom_domain[:vhost] = payload.to_json
      rescue HTTParty::ResponseError => e
        OT.le "[AddDomain.create_vhost error] %s %s %s"  % [@cust.custid, @display_domain, e]
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: cluster_safe_dump
          }
        }
      end
    end

    class RemoveDomain < OT::Logic::Base
      attr_reader :domain, :display_domain, :greenlighted
      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust)
        raise_form_error "Domain not found" unless @custom_domain
      end

      def process
        OT.ld "[RemoveDomain] Processing #{@domain} for #{@custom_domain.identifier}"
        @greenlighted = true
        @display_domain = @custom_domain[:display_domain]

        # TODO: @custom_domain.redis.multi

        @custom_domain.destroy!(@cust)

        delete_vhost
      end

      def delete_vhost
        api_key = ClusterFeatures.api_key
        if api_key.to_s.empty?
          return OT.info "[RemoveDomain.delete_vhost] Approximated API key not set"
        end
        res = OT::Utils::Approximated.delete_vhost(api_key, @display_domain)
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
      include ClusterFeatures # for cluster_safe_dump

      attr_reader :custom_domains

      def raise_concerns
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
            cluster: cluster_safe_dump
          }
        }
      end
    end

    class GetDomain < OT::Logic::Base
      include ClusterFeatures # for cluster_safe_dump

      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        # Getting the domain record based on `req.params[:domain]` (which is
        # the display_domain). That way we need to combine with the custid
        # in order to find it. It's a way of proving ownership. Vs passing the
        # domainid in the URL path which gives up the goods.
        @custom_domain = OT::CustomDomain.load(@domain_input, @cust)

        raise_form_error "Domain not found" unless @custom_domain
      end

      def process
        OT.ld "[GetDomain] Processing #{@custom_domain[:display_domain]}"

      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: cluster_safe_dump
          }
        }
      end
    end
  end
end
