# lib/onetime/mail/views/chimera.rb

# NOTE: Mustache is not ready for frozen string literals
# @see /Users/d/Projects/_/worklog/2025/journal/2025/06/16.md
#
require 'mustache'

# Chimera is a Mustache template that supports multiple extensions
#
module Onetime
  module Mail
    class Chimera < Mustache
      self.template_extension = 'html'

      # Class instance variables with class << self
      class << self
        attr_reader :partial_caching_enabled, :partial_cache

        def enable_partial_caching
          @partial_caching_enabled = true
        end

        def disable_partial_caching
          clear_partial_cache
          @partial_caching_enabled = false
        end

        def clear_partial_cache
          @partial_cache = {}
        end

        def partial_caching_enabled?
          @partial_caching_enabled.nil? || @partial_caching_enabled
        end

        def partial(name)
          path             = "#{template_path}/#{name}.#{template_extension}"
          @partial_cache ||= {}
          if @partial_cache&.key?(path)
            @partial_cache[path]
          else
            content              = File.read(path)
            @partial_cache     ||= {}
            @partial_cache[path] = content if partial_caching_enabled?
            content
          end
        end
      end

      # Initialize class instance variables
      @partial_caching_enabled = false
      # TODO: This is genuinely not ideal. We have very few partials and minimal
      # server rendered pages, but these templates are also used for emails. So
      # the "fix" for now is to disable the feature. We'll see a marginal increase
      # in web server resources which is better than playing with race conditions.
      # The proper fix is a re-implementation.
      @partial_cache           = nil

      attr_reader :options
    end
  end
end
