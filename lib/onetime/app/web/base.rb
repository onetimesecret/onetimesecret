require 'onetime/app/helpers'

class String
  def plural(int=1)
    int > 1 || int.zero? ? "#{self}s" : self
  end
  def shorten(len=50)
    return self if size <= len
    self[0..len] + "..."
  end
end

module Rack
  class File
    # from: rack 1.2.1
    # don't print out the literal filename for 404s
    def not_found
      body = "File not found\n"
      [404, {"Content-Type" => "text/plain",
         "Content-Length" => body.size.to_s,
         "X-Cascade" => "pass"},
       [body]]
    end
  end
end

module Onetime
  class App
    
    module Base
      include OT::App::Helpers
      
      attr_reader :req, :res
      attr_reader :sess, :cust
      def initialize req, res
        @req, @res = req, res
      end
    
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
    
      def carefully redirect=nil
        redirect ||= req.request_path
        # We check get here to stop an infinite redirect loop.
        # Pages redirecting from a POST can get by with the same page once. 
        redirect = '/error' if req.get? && redirect.to_s == req.request_path
        res.header['Content-Type'] ||= "text/html; charset=utf-8"
        yield
    
      rescue Redirect => ex
        res.redirect ex.location, ex.status
    
      #rescue OT::UnknownKind => ex
    
      rescue OT::MissingSecret => ex
        view = Onetime::Views::UnknownSecret.new
        res.status = 404
        res.body = view.render
    
      rescue OT::LimitExceeded => ex
        err "[limit-exceeded] #{sess.identifier.shorten(10)} (#{sess.ipaddress}): #{cust.custid}"
        err req.current_absolute_uri
        error_response "Apologies dear citizen! You have been rate limited. Try again in a few minutes."
    
      rescue Familia::NotConnected, Familia::Problem => ex
        err "#{ex.class}: #{ex.message}"
        err ex.backtrace
        error_response "An error occurred :["
    
      rescue => ex
        err "#{ex.class}: #{ex.message}"
        err req.current_absolute_uri
        err ex.backtrace.join("\n")
        error_response "An error occurred :["
      
      end
    
      def err *args
        #SYSLOG.err *args
        STDERR.puts *args
      end
      
      def not_found_response message
        view = Onetime::Views::NotFound.new req
        view.err = message
        res.status = 404
        res.body = view.render
      end
    
      def error_response message
        view = Onetime::Views::Error.new req
        view.err = message
        res.status = 401
        res.body = view.render
      end
      
    end
  end

  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=302
      @location, @status = l, s
    end
  end

end
