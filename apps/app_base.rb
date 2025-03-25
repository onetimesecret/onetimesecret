# apps/api/v1/application.rb

require 'rack'
require 'otto'
require 'json'

class BaseApplication
  attr_reader :options, :router, :rack_app

  def initialize(options = {})
    @options = options
    @router = build_router
    @rack_app = build_rack_app
  end

  def call(env)
    rack_app.call(env)
  end

  private

  def build_router
    raise NotImplementedError
  end

  def build_rack_app
    raise NotImplementedError
  end

  class << self
    attr_reader :prefix

    def inherited(subclass)
      OT.li "Registering #{subclass}"
      # Registering each implementing class with AppRegistry makes
      # it available to the main config.ru file.
      AppRegistry.register(subclass.prefix, subclass)
    end
  end
end
