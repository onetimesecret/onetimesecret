
require 'json'
require 'base64'

require_relative 'base'
require_relative '../../app_settings'


module Onetime::App
  class APIV2
    include AppSettings
    include Onetime::App::APIV2::Base

    def status
      json status: :nominal, locale: locale
    end

    def version
      json version: OT::VERSION.to_a, locale: locale
    end

    require_relative 'class_methods'
    extend ClassMethods
  end
end

# Requires at the end to avoid circular dependency
require_relative 'account'
require_relative 'challenges'
require_relative 'colonel'
require_relative 'domains'
require_relative 'secrets'
