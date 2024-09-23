# frozen_string_literal: true

# warn_indent: true

require 'mustache'

class Mustache
  self.template_extension = 'html'

  def self.partial(name)
    path = "#{template_path}/#{name}.#{template_extension}"
    if Otto.env?(:dev)
      File.read(path)
    else
      @_partial_cache ||= {}
      @_partial_cache[path] ||= File.read(path)
      @_partial_cache[path]
    end
  end
end

module Onetime
  class App

    require_relative 'views/base'

    module Views

      #
      # The VuePoint class serves as a bridge between the Ruby Rack application
      # and the Vue.js frontend. It is responsible for initializing and passing
      # JavaScript variables from the backend to the frontend.
      #
      # Example usage:
      #   view = Onetime::App::Views::VuePoint.new
      #
      class VuePoint < Onetime::App::View
        def init *args
        end
      end

      class Burn < Onetime::App::View
        def init metadata
          return handle_nil_metadata if metadata.nil?

          self[:title] = "You saved a secret"
          self[:body_class] = :generate
          self[:metadata_key] = metadata.key
          self[:metadata_shortkey] = metadata.shortkey
          self[:secret_key] = metadata.secret_key
          self[:secret_shortkey] = metadata.secret_shortkey
          self[:state] = metadata.state
          self[:recipients] = metadata.recipients
          self[:display_feedback] = false
          self[:no_cache] = true
          self[:show_metadata] = !metadata.state?(:viewed) || metadata.owner?(cust)
          secret = metadata.load_secret
          ttl = metadata.ttl.to_i  # the real ttl is always a whole number
          self[:expiration_stamp] = if ttl <= 1.minute
            '%d seconds' % ttl
          elsif ttl <= 1.hour
            '%d minutes' % ttl.in_minutes
          elsif ttl <= 1.day
            '%d hours' % ttl.in_hours
          else
            '%d days' % ttl.in_days
          end
          if secret.nil?
            self[:is_received] = metadata.state?(:received)
            self[:is_burned] = metadata.state?(:burned)
            self[:is_destroyed] = self[:is_burned] || self[:is_received]
            self[:received_date] = natural_time(metadata.received.to_i || 0)
            self[:received_date_utc] = epochformat(metadata.received.to_i || 0)
            self[:burned_date] = natural_time(   metadata.burned.to_i || 0)
            self[:burned_date_utc] = epochformat(metadata.burned.to_i || 0)
          else
            if secret.viewable?
              self[:has_passphrase] = !secret.passphrase.to_s.empty?
              self[:can_decrypt] = secret.can_decrypt?
              self[:secret_value] = secret.decrypted_value if self[:can_decrypt]
              self[:truncated] = secret.truncated?
            end
          end
        end

        def metadata_uri
          [baseuri, :private, self[:metadata_key]].join('/')
        end

        def handle_nil_metadata
          # There are errors in production where metadata is passed in as
          # nil. This temporary logging is to help shed some light.
          #
          # See https://github.com/onetimesecret/onetimesecret/issues/611
          #
          exists = begin
            OT::Metadata.exists?(req.params[:key])
          rescue StandardError => e
            OT.le "[Burn.handle_nil_metadata] Metadata.exists? raised an exception. #{e}"
            nil
          end
          OT.le "[Burn.handle_nil_metadata] Nil metadata passed to view. #{req.path} #{req.params[:key]} exists:#{exists}"
        end

      end

      class Forgot < Onetime::App::View
        def init
          self[:title] = "Forgotten Password"
          self[:body_class] = :login
          self[:with_analytics] = false
        end
      end

      class Error < Onetime::App::View
        def init *args
          self[:title] = "Oh cripes!"
        end
      end

      @translations = nil
      class Translations < Onetime::App::View
        TRANSLATIONS_PATH = File.join(OT::HOME, 'etc', 'translations.yaml') unless defined?(TRANSLATIONS_PATH)
        class << self
          attr_accessor :translations  # class instance variable
        end
        def init *args
          self[:title] = "Help us translate"
          self[:body_class] = :info
          self[:with_github_corner] = true
          self[:with_analytics] = false
          # Load translations YAML file from etc/translations.yaml
          self.class.translations ||= OT::Config.load(TRANSLATIONS_PATH)
          self[:translations] = self.class.translations
        end
      end

      class NotFound < Onetime::App::View
        def init *args
          self[:title] = "Page not found"
          self[:body_class] = :info
          self[:with_analytics] = false
        end
      end

      module Meta
        # The robots.txt file
        class Robot < Onetime::App::View
        end
      end

    end
  end
end

# These deprecated views have been suplanted by Vue.js components.
require_relative 'views/deprecated'
