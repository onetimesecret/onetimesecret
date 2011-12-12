require 'onetime/app/helpers'

class Onetime::App
  class API
    module Base
      include Onetime::App::Helpers
      
      def publically
        carefully do 
          yield
        end
      end
      
      # curl -F 'ttl=7200' -u 'delano@onetimesecret.com:4eb33c6340006d6607c813fc7e707a32f8bf5342' http://www.ot.com:7143/api/v1/generate
      def authorized allow_anonymous=false
        carefully do 
          success = false
          req.env['otto.auth'] ||= Rack::Auth::Basic::Request.new(req.env)
          auth = req.env['otto.auth']
          if auth.provided?
            OT.ld ['meth: authorized', auth.basic?, auth.credentials].inspect if Otto.env?(:dev)
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
            check_session!
          else
            raise Unauthorized, "No session or credentials" unless allow_anonymous
          end
          if cust.nil? || sess.nil? || cust.anonymous? && !sess.authenticated?
            OT.ld " [bad-cust] #{custid}"
            raise Unauthorized
          else
            cust.sessid = sess.sessid
            yield
          end
        end
      end
      
      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end
      
      def secret_not_found_response
        not_found_response "Unknown secret", :key => req.params[:key]
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