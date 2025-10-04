# lib/chimera.rb

require 'mustache'

class Chimera < Mustache
  self.template_extension  = 'html'

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
        content              = File.read(path)
        @partial_cache     ||= {}
        @partial_cache[path] = content if partial_caching_enabled?
        content
      end
    end
  end

  # Initialize class instance variables
  @partial_caching_enabled = true
  @partial_cache           = {}

  attr_reader :options
end

# Fix for Mustache 1.1.1 generator compatibility. There is
# no Mustache::VERSION to check the version. The most
# recent release was in 2015 so I think we'll be okay.
module MustacheGeneratorFix
  private

  def compile!(exp)
    case exp.first
    when :multi
      exp[1..].reduce(+'') { |sum, e| sum << compile!(e) }
    when :static
      str(exp[1])
    when :mustache
      send("on_#{exp[1]}", *exp[2..])
    else
      raise "Unhandled exp: #{exp.first}"
    end
  end
end

Mustache::Generator.prepend(MustacheGeneratorFix)
