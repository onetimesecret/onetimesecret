# lib/onetime/migration.rb

module Onetime
  # Base class for all migrations
  class BaseMigration
    attr_accessor :options

    def initialize
      @options = {}
    end

    def self.run
      new.migrate
    end

    def migrate
      raise NotImplementedError, "#{self.class} must implement #migrate"
    end

    protected

    def redis
      @redis ||= Familia.redis(6)
    end

    def log(message)
      puts message
    end
  end
end
