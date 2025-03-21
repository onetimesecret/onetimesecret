# lib/onetime/app/web/views.rb

require 'mustache'

class Chimera < Mustache
  self.template_extension = 'html'

  def options
    @options
  end

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
  module App

    require_relative 'views/base'

    module Views

      ##
      # The VuePoint class serves as a bridge between the Ruby Rack application
      # and the Vue.js frontend. It is responsible for initializing and passing
      # JavaScript variables from the backend to the frontend.
      #
      # Example usage:
      #   view = Onetime::App::Views::VuePoint.new
      #
      class VuePoint < Onetime::App::View
        self.template_name = 'index'
        def init *args
        end
      end

      class Error < Onetime::App::View
        def init *args
          self[:title] = "I'm afraid there's been an error"
        end
      end

      # The robots.txt file
      class RobotsTxt < Onetime::App::View
        self.template_name = 'robots'
        self.template_extension = 'txt'
      end

      class UnknownSecret < Onetime::App::View
        self.template_name = :index
      end

    end
  end
end
