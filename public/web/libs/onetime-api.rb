require 'httparty'
require 'uri'

# Onetime::API - v1
# 
# A basic client library for the onetimesecret.com API. 
#
# Usage:
#
#     api = Onetime::API.new 'chris@onetimesecret.com', '4dc74a03fwr9aya5qur5wa8vavo4gih1hasj6181'
#
#     api.get '/status'     
#       # => {'status' => 'nominal'}
#
#     api.post '/generate', :passphrase => 'yourspecialpassphrase'
#       # => {'value' => '3Rg8R2sfD3?a', 'metadata_key' => '...', 'secret_key' => '...'}
#       
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
      self.class.indifferent_params @response.parsed_response
    end
    class << self
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
      def indifferent_hash
        Hash.new {|hash,key| hash[key.to_s] if Symbol === key }
      end
    end
  end
end
