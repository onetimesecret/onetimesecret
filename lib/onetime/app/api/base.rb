require 'onetime/app/helpers'

class Onetime::App
  class API
    module Base
      include Onetime::App::Helpers

      def publically
        carefully do
          check_locale!
          yield
        end
      end

      # curl -F 'ttl=7200' -u 'EMAIL:APIKEY' http://LOCALHOSTNAME:7143/api/v1/generate
      def authorized allow_anonymous=false
        carefully do
          success = false
          check_locale!
          req.env['otto.auth'] ||= Rack::Auth::Basic::Request.new(req.env)
          auth = req.env['otto.auth']
          #req.env['HTTP_X_ONETIME_CLIENT']
          if auth.provided?
            raise Unauthorized unless auth.basic?
            custid, apitoken = *(auth.credentials || [])
            raise Unauthorized if custid.to_s.empty? || apitoken.to_s.empty?
            possible = OT::Customer.load custid
            raise Unauthorized if possible.nil?
            @cust = possible if possible.apitoken?(apitoken)
            unless cust.nil? || @sess = cust.load_session
              @sess = OT::Session.create req.client_ipaddress, cust.custid
            end
            sess.authenticated = true unless sess.nil?
          elsif req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
            #check_session!
            raise Unauthorized, "No session support"
          elsif !allow_anonymous
            raise Unauthorized, "No session or credentials"
          else
            @cust = OT::Customer.anonymous
            @sess = OT::Session.new req.client_ipaddress, cust.custid
          end
          if cust.nil? || sess.nil? #|| cust.anonymous? && !sess.authenticated?
            raise Unauthorized, "[bad-cust] '#{custid}' via #{req.client_ipaddress}"
          else
            cust.sessid = sess.sessid unless cust.anonymous?
            yield
          end
        end
      end

      # Find the locale of the request based on req.env['rack.locale']
      # which is set automatically by Otto v0.4.0 and greater.
      # If `locale` is specifies it will override if available.
      # If the `local` query param is set, it will override.
      def check_locale! locale=nil
        unless req.params[:locale].to_s.empty?
          locale = req.params[:locale]                                 # Use query param
          res.send_cookie :locale, locale, 30.days, Onetime.conf[:site][:ssl]
        end
        locales = req.env['rack.locale'] || []                          # Requested list
        locales.unshift locale.split('-').first if locale.is_a?(String) # Support both en and en-US
        locales << OT.conf[:locales].first                              # Ensure at least one configured locale is available
        locales = locales.uniq.reject { |l| !OT.locales.has_key?(l) }.compact
        locale = locales.first if !OT.locales.has_key?(locale)           # Default to the first available
        OT.ld [:locale, locale, locales, req.env['rack.locale'], OT.locales.keys].inspect
        req.env['ots.locale'], req.env['ots.locales'] = (@locale = locale), locales
      end

      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end

      def handle_form_error ex, redirect
        error_response ex.message
      end

      def secret_not_found_response
        not_found_response "Unknown secret", :secret_key => req.params[:key]
      end

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

    end
  end
end
