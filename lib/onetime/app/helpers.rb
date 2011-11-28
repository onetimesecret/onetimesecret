
class Onetime::App
  BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
  module Helpers
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
    
    attr_reader :req, :res
    attr_reader :sess, :cust
    def initialize req, res
      @req, @res = req, res
    end
    
  end
end