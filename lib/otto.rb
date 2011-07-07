
require 'rack/request'
require 'rack/response'
require 'rack/utils'
require 'addressable/uri'

class Otto
  LIB_HOME = File.expand_path File.dirname(__FILE__) unless defined?(Otto::LIB_HOME)
  
  module VERSION
    def self.to_s
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH]].join('.')
    end
    def self.inspect
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH], @version[:BUILD]].join('.')
    end
    def self.load_config
      require 'yaml'
      @version ||= YAML.load_file(File.join(LIB_HOME, '..', 'VERSION.yml'))
    end
  end
end

class Otto
  attr_reader :routes, :routes_literal, :routes_static, :route_definitions
  attr_reader :option, :static_route
  attr_accessor :not_found, :server_error
  def initialize path=nil, opts={}
    @routes_static =  { :GET => {} }
    @routes =         { :GET => [] }
    @routes_literal = { :GET => {} }
    @route_definitions = {}
    @option = opts.merge({
      :public => nil
    })
    load(path) unless path.nil?
    super()
  end
  alias_method :options, :option
  def load path
    path = File.expand_path(path)
    raise ArgumentError, "Bad path: #{path}" unless File.exists?(path)
    raw = File.readlines(path).select { |line| line =~ /^\w/ }.collect { |line| line.strip.split(/\s+/) }
    raw.each { |entry|
      begin
        verb, path, definition = *entry
        route = Otto::Route.new verb, path, definition
        route.otto = self
        path_clean = path.gsub /\/$/, ''
        @route_definitions[route.definition] = route
        STDERR.puts "route: #{route.pattern}"
        @routes[route.verb] ||= []
        @routes[route.verb] << route
        @routes_literal[route.verb] ||= {}
        @routes_literal[route.verb][path_clean] = route
      rescue => ex
        STDERR.puts "Bad route in #{path}: #{entry}"
      end
    }
    self
  end

  def safe_file?(path)
    globstr = File.join(option[:public], '*')
    pathstr = File.join(option[:public], path)
    File.fnmatch?(globstr, pathstr) && (File.owned?(pathstr) || File.grpowned?(pathstr)) && File.readable?(pathstr) && !File.directory?(pathstr)
  end
  
  def safe_dir?(path)
    (File.owned?(path) || File.grpowned?(path)) && File.directory?(path)
  end
  
  def add_static_path path
    if safe_file?(path)
      base_path = File.split(path).first
      # Files in the root directory can refer to themselves
      base_path = path if base_path == '/'
      static_path = File.join(option[:public], base_path)
      STDERR.puts " new static route: #{base_path} (#{path})"
      routes_static[:GET][base_path] = base_path
    end
  end
  
  def call env
    if option[:public] && safe_dir?(option[:public])
      @static_route ||= Rack::File.new(option[:public]) 
    end
    path_info = Rack::Utils.unescape(env['PATH_INFO'])
    path_info = '/' if path_info.to_s.empty?
    path_info_clean = path_info.gsub /\/$/, ''
    base_path = File.split(path_info).first
    # Files in the root directory can refer to themselves
    base_path = path_info if base_path == '/'
    http_verb = env['REQUEST_METHOD'].upcase.to_sym
    literal_routes = routes_literal[http_verb] || {}
    literal_routes.merge! routes_literal[:GET] if http_verb == :HEAD
    if static_route && http_verb == :GET && routes_static[:GET].member?(base_path)
      #STDERR.puts " request: #{path_info} (static)"
      static_route.call(env)
    elsif literal_routes.has_key?(path_info_clean)
      route = literal_routes[path_info_clean]
      #STDERR.puts " request: #{http_verb} #{path_info} (literal route: #{route.verb} #{route.path})"
      route.call(env)
    elsif static_route && http_verb == :GET && safe_file?(path_info)
      static_path = File.join(option[:public], base_path)
      STDERR.puts " new static route: #{base_path} (#{path_info})"
      routes_static[:GET][base_path] = base_path
      static_route.call(env)
    else
      extra_params = {}
      found_route = nil
      valid_routes = routes[http_verb] || []
      valid_routes.push *routes[:GET] if http_verb == :HEAD
      valid_routes.each { |route| 
        #STDERR.puts " request: #{http_verb} #{path_info} (trying route: #{route.verb} #{route.pattern})"
        if (match = route.pattern.match(path_info))
          values = match.captures.to_a
          # The first capture returned is the entire matched string b/c
          # we wrapped the entire regex in parens. We don't need it to
          # the full match.
          full_match = values.shift
          extra_params =
            if route.keys.any?
              route.keys.zip(values).inject({}) do |hash,(k,v)|
                if k == 'splat'
                  (hash[k] ||= []) << v
                else
                  hash[k] = v
                end
                hash
              end
            elsif values.any?
              {'captures' => values}
            else
              {}
            end
            found_route = route
            break
        end
      }
      found_route ||= literal_routes['/404']
      if found_route
        found_route.call env, extra_params
      else
        @not_found || Otto::Static.not_found
      end
    end
  rescue => ex
    STDERR.puts ex.message, ex.backtrace
    if found_route = literal_routes['/500']
      found_route.call env
    else
      @server_error || Otto::Static.server_error
    end
  end
  
  
  # Return the URI path for the given +route_definition+
  # e.g.
  #
  #     Otto.default.path 'YourClass.somemethod'  #=> /some/path
  #
  def uri route_definition, params={}
    #raise RuntimeError, "Not working"
    route = @route_definitions[route_definition]
    unless route.nil?
      local_params = params.clone
      local_path = route.path.clone
      if objid = local_params.delete(:id) || local_params.delete('id')
        local_path.gsub! /\*/, objid
      end
      local_params.each_pair { |k,v|
        next unless local_path.match(":#{k}")
        local_path.gsub!(":#{k}", local_params.delete(k)) 
      }
      uri = Addressable::URI.new
      uri.path = local_path
      uri.query_values = local_params
      uri.to_s
    end
  end
  
  module Static
    extend self
    def server_error
      [500, {'Content-Type'=>'text/plain'}, ["Server error"]]
    end
    def not_found
      [404, {'Content-Type'=>'text/plain'}, ["Not Found"]]
    end
    # Enable string or symbol key access to the nested params hash.
    def indifferent_params(params)
      if params.is_a?(Hash)
        params = indifferent_hash.merge(params)
        params.each do |key, value|
          next unless value.is_a?(Hash) || value.is_a?(Array)
          params[key] = indifferent_params(value)
        end
      elsif params.is_a?(Array)
        params.collect! do |value|
          if value.is_a?(Hash) || value.is_a?(Array)
            indifferent_params(value)
          else
            value
          end
        end
      end
    end
    # Creates a Hash with indifferent access.
    def indifferent_hash
      Hash.new {|hash,key| hash[key.to_s] if Symbol === key }
    end
  end
  #
  # e.g. 
  #
  #      GET   /uri/path      YourApp.method
  #      GET   /uri/path2     YourApp#method
  #
  class Route
    module ClassMethods
      attr_accessor :otto
    end
    attr_reader :verb, :path, :pattern, :method, :klass, :name, :definition, :keys, :kind
    attr_accessor :otto
    def initialize verb, path, definition
      @verb, @path, @definition = verb.to_s.upcase.to_sym, path, definition
      @pattern, @keys = *compile(@path)
      if !@definition.index('.').nil?
        @klass, @name = @definition.split('.')
        @kind = :class
      elsif !@definition.index('#').nil?
        @klass, @name = @definition.split('#')
        @kind = :instance
      else
        raise ArgumentError, "Bad definition: #{@definition}"
      end
      @klass = eval(@klass)
      #@method = eval(@klass).method(@name)
    end
    def pattern_regexp
      Regexp.new(@path.gsub(/\/\*/, '/.+'))
    end
    def call(env, extra_params={})
      extra_params ||= {}
      req = Rack::Request.new(env)
      res = Rack::Response.new
      req.extend Otto::RequestHelpers
      res.extend Otto::ResponseHelpers
      res.request = req
      req.params.merge! extra_params
      req.params.replace Otto::Static.indifferent_params(req.params)
      klass.extend Otto::Route::ClassMethods
      klass.otto = self.otto
      case kind
      when :instance
        inst = klass.new req, res
        inst.send(name)
      when :class
        klass.send(name, req, res)
      else
        raise RuntimeError, "Unsupported kind for #{@definition}: #{kind}"
      end
      res.body = [res.body] unless res.body.respond_to?(:each)
      res.finish
    end
    # Brazenly borrowed from Sinatra::Base:
    # https://github.com/sinatra/sinatra/blob/v1.2.6/lib/sinatra/base.rb#L1156
    def compile(path)
      keys = []
      if path.respond_to? :to_str
        special_chars = %w{. + ( ) $}
        pattern =
          path.to_str.gsub(/((:\w+)|[\*#{special_chars.join}])/) do |match|
            case match
            when "*"
              keys << 'splat'
              "(.*?)"
            when *special_chars
              Regexp.escape(match)
            else
              keys << $2[1..-1]
              "([^/?#]+)"
            end
          end
        # Wrap the regex in parens so the regex works properly.
        # They can fail when there's an | for example (matching only the last one).
        # Note: this means we also need to remove the first matched value.
        [/\A(#{pattern})\z/, keys]
      elsif path.respond_to?(:keys) && path.respond_to?(:match)
        [path, path.keys]
      elsif path.respond_to?(:names) && path.respond_to?(:match)
        [path, path.names]
      elsif path.respond_to? :match
        [path, keys]
      else
        raise TypeError, path
      end
    end
  end
  class << self
    def default
      @default ||= Otto.new
      @default
    end
    def load path
      default.load path
    end
    def path definition, params={}
      default.path definition, params
    end
    def routes
      default.routes
    end
    def env? *guesses
      !guesses.flatten.select { |n| ENV['RACK_ENV'].to_s == n.to_s }.empty?
    end
  end
  module RequestHelpers
    def user_agent
      env['HTTP_USER_AGENT'] || '[no-user-agent]'
    end
    
    # HTTP_X_FORWARDED_FOR is from the ELB (non-https only)
    # and it can take the form: 74.121.244.2, 10.252.130.147
    # HTTP_X_REAL_IP is from nginx
    # REMOTE_ADDR is from thin
    # There's no way to get the client IP address in HTTPS. 
    def client_ipaddress
      env['HTTP_X_FORWARDED_FOR'].to_s.split(/,\s*/).first ||
      env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
    end
  
    def request_method
      env['REQUEST_METHOD']
    end
    
    def current_server
      [current_server_name, env['SERVER_PORT']].join(':')
    end

    def current_server_name
      env['SERVER_NAME']
    end
        
    def http_host
      env['HTTP_HOST']
    end
    def request_path
      env['REQUEST_PATH']
    end
    
    def request_uri
      env['REQUEST_URI']
    end
        
    def root_path
      env['SCRIPT_NAME']
    end
    
    def absolute_suri host=current_server_name
      prefix = local? ? 'http://' : 'https://'
      [prefix, host, request_path].join
    end
    
    def local?
      Otto.env?(:dev, :development) && client_ipaddress == '127.0.0.1' 
    end
    
    def secure?
      # X-Scheme is set by nginx
      # X-FORWARDED-PROTO is set by elastic load balancer
      (env['HTTP_X_FORWARDED_PROTO'] == 'https' || env['HTTP_X_SCHEME'] == "https")
    end 
    
    def cookie name
      cookies[name.to_s]
    end
    
    def cookie? name
      !cookie(name).to_s.empty?
    end
    
    def current_absolute_uri
      prefix = secure? && !local? ? 'https://' : 'http://'
      [prefix, http_host, request_path].join
    end
    
  end
  module ResponseHelpers
    attr_accessor :request
    def send_secure_cookie name, value, ttl
      send_cookie name, value, ttl, true
    end
    def send_cookie name, value, ttl, secure=true
      secure = false if request.local?
      opts = {
        :value    => value, 
        :path     => '/', 
        :expires  => (Time.now + ttl + 10).utc,
        :secure   => secure
      }
      opts[:domain] = request.env['SERVER_NAME']
      #pp [:cookie, name, opts]
      set_cookie name, opts
    end
    def delete_cookie name
      send_cookie name, nil, -1.day
    end
  end
end