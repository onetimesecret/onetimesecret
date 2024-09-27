
require 'json'
require 'base64'

require_relative 'base'
require_relative '../../app_settings'


module Onetime::App
  class APIV2
    include AppSettings
    include Onetime::App::APIV2::Base

    def status
      authorized do
        json status: :nominal, locale: locale
      end
    end

    def version
      publically do
        json version: OT::VERSION.to_a, locale: locale
      end
    end

    def get_supported_locales
      publically do
        supported_locales = OT.conf.fetch(:locales, []).map(&:to_s)
        default_locale = supported_locales.first
        json locales: supported_locales, default_locale: default_locale, locale: locale
      end
    end

    def validate_shrimp
      publically do
        shrimp = request.env['HTTP_O_SHRIMP'].to_s
        halt(400, json(error: 'Missing O-Shrimp header')) if shrimp.empty?

        begin
          # Attempt to validate the shrimp
          is_valid = validate_shrimp(shrimp)
        rescue OT::BadShrimp => e
          # If a BadShrimp exception is raised, log it and set is_valid to false
          OT.ld "BadShrimp exception: #{e.message}"
          is_valid = false
        end

        json isValid: is_valid
      end
    end

  end
end

# Requires at the end to avoid circular dependency
require_relative 'account'
require_relative 'challenges'
require_relative 'colonel'
require_relative 'domains'
require_relative 'secrets'
