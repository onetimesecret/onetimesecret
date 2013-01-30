require 'net/http'
require 'uri'

module StatHat
  class API
    def self.post_value(stat_key, user_key, value)
      args = { :key => stat_key,
        :ukey => user_key,
        :value => value }
      resp = Net::HTTP.post_form(URI.parse("http://api.stathat.com/v"), args)
      return self.response_valid?(resp)
    end

    def self.post_count(stat_key, user_key, count)
      args = { :key => stat_key,
        :ukey => user_key,
        :value => count }
      resp = Net::HTTP.post_form(URI.parse("http://api.stathat.com/c"), args)
      return self.response_valid?(resp)
    end

    def self.ez_post_value(stat_name, account_email, value)
      args = { :stat => stat_name,
        :email => account_email,
        :value => value }
      resp = Net::HTTP.post_form(URI.parse("http://api.stathat.com/ez"), args)
      return self.response_valid?(resp)
    end

    def self.ez_post_count(stat_name, account_email, count)
      args = { :stat => stat_name,
        :email => account_email,
        :count => count }
      resp = Net::HTTP.post_form(URI.parse("http://api.stathat.com/ez"), args)
      return self.response_valid?(resp)
    end

    def self.response_valid?(response)
      return response.code == "200"
    end
  end
end
