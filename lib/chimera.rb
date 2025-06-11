# lib/chimera.rb

require 'mustache'

# Chimera is a Mustache template that supports multiple extensions
#
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
      path = "#{template_path}/#{name}.#{template_extension}"

      if @partial_cache&.key?(path)
        @partial_cache[path]
      else
        content = File.read(path)
        @partial_cache ||= {}
        @partial_cache[path] = content if partial_caching_enabled?
        content
      end
    end
  end

  # Initialize class instance variables
  @partial_caching_enabled = true
  @partial_cache = {}

  attr_reader :options
  end
