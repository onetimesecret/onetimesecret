# apps/base_application.rb

require 'rack'
require 'otto'
require 'json'

require_relative 'app_registry'

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
    @uri_prefix = nil

    attr_reader :uri_prefix

    # Tracks subclasses for deferred registration
    # @param subclass [Class] The class inheriting from BaseApplication
    # @return [void]
    def inherited(subclass)
      # Keep track subclasses without immediate registration
      AppRegistry.track_application(subclass)
      OT.ld "BaseApplication.inherited: #{subclass} registered with AppRegistry"
    end
  end
end
