
class Onetime::App
  BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
  module Helpers
    
    attr_reader :req, :res
    attr_reader :sess, :cust
    attr_reader :ignoreshrimp
    def initialize req, res
      @req, @res = req, res
    end
    
    def authenticated redirect=nil
      carefully(redirect) do 
        sess.authenticated? ? yield : res.redirect(('/'))
      end
    end
    
    def colonels redirect=nil
      carefully(redirect) do
        sess.authenticated? && cust.role?(:colonel) ? yield : res.redirect(('/'))
      end
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
      @sess ||= OT::Session.new
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