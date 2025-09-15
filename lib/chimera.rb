# lib/chimera.rb

require 'erb'

class Chimera
  class << self
    attr_accessor :template_path, :template_extension, :view_namespace, :view_path, :template_name
    attr_reader :partial_caching_enabled, :partial_cache

    def inherited(subclass)
      # Set default values for subclasses
      subclass.template_extension = 'html.erb'
      super
    end

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
      path = "#{template_path}/partials/#{name}.#{template_extension}"

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
  @template_extension = 'html.erb'
  @partial_caching_enabled = true
  @partial_cache           = {}

  attr_reader :options

  # Access to template variables as hash keys (similar to Mustache behavior)
  def [](key)
    instance_variable_get("@#{key}")
  end

  def []=(key, value)
    instance_variable_set("@#{key}", value)
  end

  # Make template variables accessible as method calls (for ERB compatibility)
  def method_missing(method_name, *args, &block)
    if args.empty? && !block_given? && instance_variable_defined?("@#{method_name}")
      instance_variable_get("@#{method_name}")
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    instance_variable_defined?("@#{method_name}") || super
  end

  # Render the template with ERB
  def render(template_name = nil)
    template_name ||= self.class.template_name || infer_template_name
    return "Template name could not be determined" if template_name.nil?
    template_path = File.join(self.class.template_path, "#{template_name}.#{self.class.template_extension}")

    erb_content = File.read(template_path)
    erb = ERB.new(erb_content)
    erb.result(binding)
  end

  # Render a partial template
  def render_partial(name)
    partial_path = File.join(self.class.template_path, 'partials', "#{name}.#{self.class.template_extension}")
    erb_content = File.read(partial_path)
    erb = ERB.new(erb_content)
    erb.result(binding)
  end

  protected

  def infer_template_name
    self.class.name.split('::').last.downcase
  end
end

# ERB-based template rendering system
# Provides Mustache-like interface with ERB backend
