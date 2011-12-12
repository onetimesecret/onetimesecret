
class Onetime::App
  class Unauthorized < RuntimeError
  end
  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=302
      @location, @status = l, s
    end
  end
  BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
  module Helpers
    
    attr_reader :req, :res
    attr_reader :sess, :cust
    attr_reader :ignoreshrimp
    def initialize req, res
      @req, @res = req, res
    end
    
    def plan
      @plan = Onetime::Plan.plans[cust.planid] unless cust.nil?
      @plan ||= Onetime::Plan.plans['anonymous']
      @plan
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
    
    rescue OT::BadShrimp => ex
      sess.set_error_message "Please go back, refresh the page, and try again."
      res.redirect redirect
    
    rescue OT::FormError => ex
      sess.set_form_fields ex.form_fields
      sess.set_error_message ex.message
      res.redirect redirect
    
    rescue OT::MissingSecret => ex
      view = Onetime::App::Views::UnknownSecret.new req, sess, cust
      res.status = 404
      res.body = view.render
    
    rescue OT::LimitExceeded => ex
      err "[limit-exceeded] #{cust.custid}(#{sess.ipaddress}): #{ex.event}(#{ex.count}) #{sess.identifier.shorten(10)}"
      err req.current_absolute_uri
      error_response "Apologies dear citizen! You have been rate limited. Try again in a few minutes."
    
    rescue Familia::NotConnected, Familia::Problem => ex
      err "#{ex.class}: #{ex.message}"
      err ex.backtrace
      error_response "An error occurred :["
    
    rescue Errno::ECONNREFUSED => ex
      OT.info "Redis is down: #{ex.message}"
      raise OT::Problem.new("OT will be back shortly!")
    
    rescue => ex
      err "#{ex.class}: #{ex.message}"
      err req.current_absolute_uri
      err ex.backtrace.join("\n")
      error_response "An error occurred :["
    
    ensure
      @sess ||= OT::Session.new :failover
      @cust ||= OT::Customer.anonymous
    end
    
    def check_shrimp!
      return unless req.post? || req.put? || req.delete?
      attempted_shrimp = req.params[:shrimp]
      ### NOTE: MUST FAIL WHEN NO SHRIMP OTHERWISE YOU CAN
      ### JUST SUBMIT A FORM WITHOUT ANY SHRIMP WHATSOEVER.
      OT.ld "SHRIMP for #{cust.custid}@#{req.path}: #{attempted_shrimp}"
      unless sess.shrimp?(attempted_shrimp) || ignoreshrimp
        shrimp = (sess.shrimp || '[noshrimp]').clone
        sess.clear_shrimp!  # assume the shrimp is being tampered with
        ex = OT::BadShrimp.new(req.path, cust.custid, attempted_shrimp, shrimp)
        raise ex
      end
    end
    
    def check_session!
      if req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
        @sess = OT::Session.load req.cookie(:sess)
      else
        @sess = OT::Session.create req.client_ipaddress, req.user_agent
      end
      if sess
        sess.update_fields  # calls update_time!
        # Only set the cookie after it's been saved
        res.send_cookie :sess, sess.sessid, sess.ttl
        @cust = sess.load_customer
      end
      @sess ||= OT::Session.new :check_session
      @cust ||= OT::Customer.anonymous
      if cust.anonymous?
        sess.authenticated = false 
      elsif cust.verified.to_s != 'true'
        sess.authenticated = false 
      end
      OT.ld "[sessid] #{sess.sessid} #{cust.custid}"
    end
    
    def err *args
      #SYSLOG.err *args
      STDERR.puts *args
    end
    
    def deny_agents! *agents
      BADAGENTS.flatten.each do |agent|
        if req.user_agent =~ /#{agent}/i
          raise Redirect.new('/')
        end
      end
    end
    
    def app_path *paths
      paths = paths.flatten.compact
      paths.unshift req.script_name
      paths.join('/').gsub '//', '/'
    end
    
  end
end