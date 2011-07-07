
require 'mustache'

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



module Site
  module Views
  end
  class View < Mustache
    self.template_path = './app/site/templates'
    self.view_namespace = Site::Views
    self.view_path = './app/site/views'
    attr_accessor :err
    def initialize req=nil, res=nil
      self[:subtitle] = "One Time"
      init if respond_to? :init
    end
    def baseuri
      scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
      [scheme, Onetime.conf[:site][:host]].join
    end
  end
  module Base
    def carefully req, res, redirect=nil
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
      
    rescue Familia::NotConnected, Familia::Problem => ex
      err "#{ex.class}: #{ex.message}"
      err ex.backtrace
      #BS::Problem.report! req.request_method, req.request_uri, sess, cust, "#{ex.class}: #{ex.message}"
      error_response req, res, "An error occurred :["
    
    rescue => ex
      err "#{ex.class}: #{ex.message}"
      err req.current_absolute_uri
      err ex.backtrace.join("\n")
      #BS::Problem.report! req.request_method, req.request_uri, sess, cust, "#{ex.class}: #{ex.message}"
      error_response req, res, "An error occurred :["
      
    end
    
    def err *args
      #SYSLOG.err *args
      STDERR.puts *args
    end
    
    def not_found_response req, res, message
      view = Site::Views::NotFound.new req
      view.err = message
      res.status = 404
      res.body = view.render
    end
    
    def error_response req, res, message
      view = Site::Views::Error.new req
      view.err = message
      res.status = 401
      res.body = view.render
    end
  end
  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=304
      @location, @status = l, s
    end
  end
end




