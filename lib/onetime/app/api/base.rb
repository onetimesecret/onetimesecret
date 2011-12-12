require 'onetime/app/helpers'

class Onetime::App
  class API
    module Base
      include Onetime::App::Helpers
      
      
      def anonymous
        carefully do 
          begin
            @cust = OT::Customer.anonymous
            if req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
              @sess = OT::Session.load req.cookie(:sess)
            else
              @sess = OT::Session.create req.client_ipaddress, @cust.custid, req.user_agent
            end
            if @sess
              @sess.update_fields  # calls update_time!
              # Only set the cookie after it's been saved
              res.send_cookie :sess, @sess.sessid, @sess.ttl
            end
          end
          yield
        end
      end
      
      def authorized allow_anonymous=false
        carefully do 
          success = false
          req.env['otto.auth'] ||= Rack::Auth::Basic::Request.new(req.env)
          auth = req.env['otto.auth']
          if auth.provided?
            OT.ld ['meth: authorized', auth.basic?, auth.credentials].inspect if Otto.env?(:dev)
            raise Unsupported unless auth.basic?
            custid, apikey = *(auth.credentials || [])
            raise Unauthorized if custid.to_s.empty? || apikey.to_s.empty?
            @cust = OT::Customer.from_redis custid
            raise Unauthorized if @cust.nil?
            @sess = @cust.session || OT::Session.new(req.client_ipaddress, cust.custid)
          elsif req.cookie?(:sess)
            if req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
              raise "TODO: from_redis doesn't exist. Use load."
              @sess = OT::Session.from_redis(req.cookie(:sess))
              @sess.location = req.current_absolute_uri
              if @sess.stale?
                @sess.destroy!
                @sess.regenerate_id 
              end
              @cust = @sess.load_customer
            else
              if req.cookie?(:sess)
                res.delete_cookie :sess 
                OT.li "delete cookie"
              end
              @cust = OT::Customer.anonymous
              @sess = OT::Session.new req.client_ipaddress, cust.custid
            end
            @sess.set :noredirect, true if req.params[:noredirect]
          else
            if allow_anonymous
              OT.info "TODO"
            else
              raise Unauthorized, "No session or credentials"
            end
          end
          if @sess
            @sess.agent, @sess.ipaddress = req.user_agent, req.client_ipaddress
            @sess.update_time! # calls save
            # Only set the cookie after it's been saved
            res.send_cookie :sess, @sess.sessid, @sess.ttl
          end
        
          if !cust.nil? && cust.apikey?(apikey)
            success = true
            @sess = OT::Session.new req.client_ipaddress, cust.custid
            @sess.authorized = true
            @cust = cust
            @cust.sessid = @sess.sessid
            yield
          else
            OT.ld " [bad-cust] #{custid}"
            raise Unauthorized
          end
        end
      end
      
      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end
      
      def not_found hsh
        res.status = 404
        json hsh
      end
      
    end
  end
end