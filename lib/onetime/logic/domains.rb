
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

    class AddDomain < OT::Logic::Base
      attr_reader :modified, :greenlighted, :custom_domain

      def process_params
        OT.ld "[AddDomain] Normalizing #{@domain}"
        @domain = OT::CustomDomain.normalize(params[:domain])  # returns a string or nil
      end

      def raise_concerns
        @modified ||= []
        OT.ld "[AddDomain] Raising concerns #{@domain}"
        limit_action :add_domain
        raise_form_error "Please enter a domain" if @domain.to_s.empty?
        raise_form_error "Not a valid domain" unless OT::CustomDomain.valid?(@domain)
        # Don't need to do a bunch of validation checks here. If a value
        # is provided and it passes as valid, it's valid. If another account
        # has verified the same domain, that's fine. Both accounts can generate
        # secret links for that domain, and the links will be valid for both accounts.
        #
        #if OT::CustomDomain.exists?(@domain)
        #  raise_form_error "That domain is not available"
        #end
        #
      end

      def process
        @greenlighted = true
        OT.ld "[AddDomain] Processing #{@domain}"
        @custom_domain = OT::CustomDomain.create(@domain, custid=@cust.custid)
      end

      def success_data
        { custid: @cust.custid, custom_domain: custom_domain }
      end
    end

  end
end
