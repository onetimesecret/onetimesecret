
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
        if %w{www yourcompany mycompany admin ots secure secrets}.member?(@cname)
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

      private

      def form_fields
        properties.merge :tabindex => params[:tabindex], :cname => cname
      end
    end

    class CustomDomain < OT::Logic::Base
      attr_reader :modified, :greenlighted

      def process_params
        @currentp = self.class.normalize_password(params[:currentp])

      end

      def raise_concerns
        @modified ||= []
        #limit_action :update_account
      end

      def process

      end

    end

  end
end
