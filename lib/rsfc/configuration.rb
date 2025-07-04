# lib/rsfc/configuration.rb

module RSFC
  # Configuration management for RSFC library
  #
  # Provides a clean, testable alternative to global configuration access.
  # Supports block-based configuration typical of Ruby gems and dependency injection.
  #
  # Usage:
  #   RSFC.configure do |config|
  #     config.default_locale = 'en'
  #     config.template_paths = ['app/templates', 'lib/templates']
  #     config.features = { account_creation: true }
  #   end
  class Configuration
    # Core application settings
    attr_accessor :default_locale, :app_environment, :development_enabled

    # Template settings
    attr_accessor :template_paths, :template_root, :cache_templates

    # Security settings  
    attr_accessor :csrf_token_name, :nonce_header_name

    # Feature flags
    attr_accessor :features

    # Site configuration
    attr_accessor :site_host, :site_ssl_enabled, :api_base_url

    # Performance settings
    attr_accessor :cache_parsed_templates, :cache_ttl

    def initialize
      # Set sensible defaults
      @default_locale = 'en'
      @app_environment = 'development'
      @development_enabled = false
      @template_paths = []
      @cache_templates = true
      @csrf_token_name = 'csrf_token'
      @nonce_header_name = 'nonce'
      @features = {}
      @site_ssl_enabled = false
      @cache_parsed_templates = true
      @cache_ttl = 3600 # 1 hour
    end

    # Build API base URL from site configuration
    def api_base_url
      return @api_base_url if @api_base_url

      return nil unless @site_host

      protocol = @site_ssl_enabled ? 'https' : 'http'
      "#{protocol}://#{@site_host}/api"
    end

    # Check if development mode is enabled
    def development?
      @development_enabled || @app_environment == 'development'
    end

    # Check if production mode
    def production?
      @app_environment == 'production'
    end

    # Get feature flag value
    def feature_enabled?(feature_name)
      @features[feature_name] || @features[feature_name.to_s] || false
    end

    # Validate configuration
    def validate!
      errors = []

      # Validate locale
      if @default_locale.nil? || @default_locale.empty?
        errors << "default_locale cannot be empty"
      end

      # Validate template paths exist if specified
      @template_paths.each do |path|
        unless Dir.exist?(path)
          errors << "Template path does not exist: #{path}"
        end
      end

      # Validate cache TTL
      if @cache_ttl && @cache_ttl <= 0
        errors << "cache_ttl must be positive"
      end

      raise ConfigurationError, "Configuration errors: #{errors.join(', ')}" unless errors.empty?
    end

    # Deep freeze configuration to prevent modification after setup
    def freeze!
      @features.freeze
      @template_paths.freeze
      freeze
    end

    class ConfigurationError < StandardError; end
  end

  class << self
    # Global configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure RSFC with block
    def configure
      yield(configuration) if block_given?
      configuration.validate!
      configuration.freeze!
      configuration
    end

    # Reset configuration (useful for testing)
    def reset_configuration!
      @configuration = nil
    end

    # Shorthand access to configuration
    def config
      configuration
    end
  end
end