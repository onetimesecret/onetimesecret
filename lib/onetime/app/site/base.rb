
require 'mustache'

class String
  def plural(int=1)
    int > 1 || int.zero? ? "#{self}s" : self
  end
  def shorten(len=50)
    return self if size <= len
    self[0..len] + "..."
  end
end

class Mustache
  def self.partial(name)
    path = "#{template_path}/#{name}.#{template_extension}"
    if Otto.env?(:dev)
      File.read(path)
    else
      @_partial_cache ||= {}
      @_partial_cache[path] ||= File.read(path)
      @_partial_cache[path]
    end
  end
end


module Onetime
  module Base
    BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
    attr_reader :req, :res
    attr_reader :sess, :cust
    def initialize req, res
      @req, @res = req, res
    end
    def deny_agents! *agents
      BADAGENTS.flatten.each do |agent|
        if req.user_agent =~ /#{agent}/i
          raise Redirect.new('/')
        end
      end
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
      
    #rescue BS::Problem => ex
    #  err "#{ex.class}: #{ex.message}"
    #  err ex.backtrace
    #  ex.report! req.request_method, req.request_uri, sess, cust, "#{ex.class}: #{ex.message}"
    #  error_response "You found a bug. Feel free to tell Tucker."
    
    rescue OT::MissingSecret => ex
      view = Onetime::Views::UnknownSecret.new
      res.status = 404
      res.body = view.render
      
    rescue Familia::NotConnected, Familia::Problem => ex
      err "#{ex.class}: #{ex.message}"
      err ex.backtrace
      #BS::Problem.report! req.request_method, req.request_uri, sess, cust, "#{ex.class}: #{ex.message}"
      error_response "An error occurred :["
    
    rescue => ex
      err "#{ex.class}: #{ex.message}"
      err req.current_absolute_uri
      err ex.backtrace.join("\n")
      #BS::Problem.report! req.request_method, req.request_uri, sess, cust, "#{ex.class}: #{ex.message}"
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
  module Views
  end
  class View < Mustache
    self.template_path = './templates/site'
    self.view_namespace = Onetime::Views
    self.view_path = './app/site/views'
    attr_accessor :err
    def initialize req=nil, res=nil, *args
      self[:subtitle] = "One Time"
      self[:monitored_link] = false
      self[:ot_version] = OT::VERSION
      if req && req.params[:errno] && Onetime::ERRNO.has_key?(req.params[:errno])
        self.err = Onetime::ERRNO[req.params[:errno]]
      end
      init *args if respond_to? :init
    end
    def baseuri
      scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
      [scheme, Onetime.conf[:site][:host]].join
    end
    protected
    def natural_time(e)
      return if e.nil?
      val = Time.now.utc.to_i - e.to_i
      #puts val
      if val < 10 
        result = 'a moment ago'
      elsif val < 40  
        result = 'about ' + (val * 1.5).to_i.to_s.slice(0,1) + '0 seconds ago'
      elsif val < 60 
        result = 'about a minute ago'
      elsif val < 60 * 1.3  
        result = "1 minute ago"
      elsif val < 60 * 2  
        result = "2 minutes ago"
      elsif val < 60 * 50  
        result = "#{(val / 60).to_i} minutes ago"
      elsif val < 3600 * 1.4 
        result = 'about 1 hour ago'
      elsif val < 3600 * (24 / 1.02) 
        result = "about #{(val / 60 / 60 * 1.02).to_i} hours ago"
      elsif val < 3600 * 24 * 1.6
        result = Time.at(e.to_i).strftime("yesterday").downcase
      elsif val < 3600 * 24 * 7
        result = Time.at(e.to_i).strftime("on %A").downcase
      #elsif val < 3600 * 24 * 11
      #  result = Time.at(e.to_i).strftime("last %A").downcase
      else
        weeks = (val / 3600.0/24.0/7).to_i
        result = Time.at(e.to_i).strftime("#{weeks} #{'week'.plural(weeks)} ago").downcase
      end
      result
    end
  end

  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=302
      @location, @status = l, s
    end
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