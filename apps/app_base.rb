# apps/app_base.rb

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
    @prefix = nil
    @subclasses = nil

    attr_reader :prefix, :subclasses

    # Tracks subclasses for deferred registration
    # @param subclass [Class] The class inheriting from BaseApplication
    # @return [void]
    def inherited(subclass)
      # Keep track subclasses without immediate registration
      (@subclasses ||= []) << subclass
      OT.ld "Tracking #{subclass} for registration"
    end

    def development?
      ENV['RACK_ENV'] =~ /\A(dev|development)\z/
    end

    def production?
      ENV['RACK_ENV'] =~ /\A(prod|production)\z/
    end
  end
end
