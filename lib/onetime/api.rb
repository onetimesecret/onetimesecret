require 'httparty'
require 'uri'

module Onetime
  class API
    include HTTParty
    base_uri 'https://onetimesecret.com/api'
    format :json
    attr_reader :opts, :response, :custid, :key, :default_params
    attr_accessor :apiversion
    def initialize custid=nil, key=nil, opts={}
      unless ENV['ONETIME_HOST'].to_s.empty?
        self.class.base_uri ENV['ONETIME_HOST'] 
      end
      @apiversion = opts.delete(:apiversion) || opts.delete('apiversion') || 1
      @opts = opts
      @default_params = {}
      @custid = custid || ENV['ONETIME_ACCOUNT']
      @key = key || ENV['ONETIME_TOKEN']
      unless @custid.to_s.empty? || @key.to_s.empty?
        opts[:basic_auth] ||= { :username => @custid, :password => @key }
      end
    end
    def get path, params=nil
      opts = self.opts.clone
      opts[:query] = (params || {}).merge default_params
      execute_request :get, path, opts
    end
    def post path, params=nil
      opts = self.opts.clone
      opts[:body] = (params || {}).merge default_params
      execute_request :post, path, opts
    end
    def base_uri path
      uri = URI.parse self.class.base_uri
      uri.path = uri_path(path)
      uri.to_s
    end
    def uri_path *args
      args.unshift ['', "v#{apiversion}"] # force leading slash and version
      path = args.flatten.join('/')
      path.gsub '//', '/'
    end
    private
    def execute_request meth, path, opts
      path = uri_path [path]
      @response = self.class.send meth, path, opts
      OT::Utils.indifferent_params @response.parsed_response
    end
    class << self
    end    
    class Unauthorized < RuntimeError
    end
  end
end
