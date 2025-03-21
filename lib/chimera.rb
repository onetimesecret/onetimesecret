# lib/chimera.rb

class Chimera < Mustache
  self.template_extension = 'html'

  # Cache control - enabled by default for performance
  @@partial_caching_enabled = true
  @@partial_cache = {}

  # Cache control methods
  def self.enable_partial_caching
    @@partial_caching_enabled = true
  end

  def self.disable_partial_caching
    clear_partial_cache
    @@partial_caching_enabled = false
  end

  def self.clear_partial_cache
    @@partial_cache = {}
  end

  def self.partial_caching_enabled?
    @@partial_caching_enabled
  end

  def options
    @options
  end

  def self.partial(name)
    path = "#{template_path}/#{name}.#{template_extension}"

    if @@template_cache.key?(path)
      @@partial_cache[path]
    else
      content = File.read(path)
      @@partial_cache[path] = content if partial_caching_enabled?
      content
    end
  end
end
