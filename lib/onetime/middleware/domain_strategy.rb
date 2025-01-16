# lib/onetime/middleware/domain_strategy.rb

module Onetime
  # Middleware for handling and validating domain types in incoming requests.
  #
  # This class normalizes the incoming host, determines its state (canonical, subdomain,
  # custom, or invalid), and updates the Rack environment with the domain strategy.
  class DomainStrategy
    # Domain states
    unless defined?(STATES)
      STATES = {
        canonical: :canonical,   # Matches configured domain exactly
        subdomain: :subdomain,  # Valid subdomain of canonical domain
        custom: :custom,        # Different valid domain
        invalid: :invalid      # Invalid/malformed domain
      }.freeze

      # Domain validation constants
      MAX_DOMAIN_LENGTH = 253
      MAX_LABEL_LENGTH = 63
    end

    # Initializes the DomainStrategy middleware.
    #
    # @param app [Object] The Rack application.
    def initialize(app)
      @app = app
      @config = OT.conf.fetch(:site, {})
      @canonical_domain = self.class.normalize_canonical_domain(@config)
    end

    # Processes the incoming request and updates the Rack environment with the domain strategy.
    #
    # @param env [Hash] The Rack environment.
    # @return [Array] The Rack response.
    def call(env)
      display_domain = nil
      domain_strategy = STATES[:canonical]

      if domains_enabled?
        display_domain = env[Rack::DetectHost.result_field_name]
        domain_strategy = process_domain(display_domain).value # canonical, custom, etc
      end

      env['onetime.display_domain'] = display_domain
      env['onetime.domain_strategy'] = domain_strategy
      OT.ld "[DomainStrategy]: strategy=#{domain_strategy} host=#{display_domain.inspect}"

      @app.call(env)
    end

    # Normalizes the canonical domain from the configuration.
    #
    # @return [String, nil] The normalized canonical domain or nil if not configured.
    def self.normalize_canonical_domain(config)
      domain = if config.dig(:domains, :enabled) && config.dig(:domains, :default)
                 config.dig(:domains, :default)
               else
                 config.fetch(:host, nil)
               end
      Normalizer.normalize(domain)
    end

    private

    # Processes the domain and determines its state.
    #
    # @param host [String] The host to process.
    # @return [State] The state of the domain.
    def process_domain(host)
      return State.new(STATES[:canonical]) if host.nil?

      normalized = Normalizer.normalize(host)
      return State.new(STATES[:invalid]) unless normalized

      determine_state(normalized)
    end

    # Determines the state of the normalized host.
    #
    # @param normalized_host [String] The normalized host.
    # @return [State] The state of the domain.
    def determine_state(normalized_host)
      return State.new(STATES[:canonical]) if normalized_host == @canonical_domain

      domain_parts = Parser.parse(normalized_host)
      return State.new(STATES[:invalid]) unless domain_parts.valid?

      if is_subdomain?(normalized_host, domain_parts)
        State.new(STATES[:subdomain], normalized_host)
      else
        State.new(STATES[:custom], normalized_host)
      end
    end

    # Checks if the given host is a subdomain of the canonical domain.
    #
    # @param host [String] The host to check.
    # @param domain_parts [Parts] The parsed domain parts.
    # @return [Boolean] True if the host is a subdomain, false otherwise.
    def is_subdomain?(host, domain_parts)
      canonical_parts = @canonical_domain.split('.')
      request_parts = domain_parts.parts

      return false if request_parts.length <= canonical_parts.length

      suffix = canonical_parts.join('.')
      return false unless host.end_with?(".#{suffix}")

      subdomain_parts = Parser::Parts.new(
        request_parts[0...-canonical_parts.length]
      )

      subdomain_parts.valid?
    end

    # Checks if domains are enabled in the configuration.
    #
    # @return [Boolean] True if domains are enabled, false otherwise.
    def domains_enabled?
      @config.dig(:domains, :enabled)
    end

    # Module for normalizing domain names.
    module Normalizer
      class << self
        # Normalizes the given host.
        #
        # @param host [String] The host to normalize.
        # @return [String, nil] The normalized host or nil if invalid.
        def normalize(host)
          return nil if host.nil? || host.empty?

          normalized = host.strip
                           .downcase
                           .split(':').first # Remove port

          begin
            normalized = SimpleIDN.to_ascii(normalized)
          rescue
            return nil
          end

          return nil if invalid_format?(normalized)
          normalized
        end

        private

        # Checks if the host has an invalid format.
        #
        # @param host [String] The host to check.
        # @return [Boolean] True if the host has an invalid format, false otherwise.
        def invalid_format?(host)
          host.length > MAX_DOMAIN_LENGTH ||
            host.start_with?('.') ||
            host.end_with?('.') ||
            host.include?('..') ||
            host.split('.').any? { |part| part.length > MAX_LABEL_LENGTH }
        end
      end
    end

    # Module for parsing domain names.
    module Parser
      # Represents the parts of a domain name.
      class Parts
        attr_reader :parts

        # Initializes a new Parts object.
        #
        # @param parts [Array<String>] The parts of the domain name.
        def initialize(parts)
          @parts = parts
        end

        # Checks if the domain parts are valid.
        #
        # @return [Boolean] True if the domain parts are valid, false otherwise.
        def valid?
          return false if parts.empty?
          parts.all? { |part| valid_label?(part) }
        end

        private

        # Checks if a domain label is valid.
        #
        # @param part [String] The domain label to check.
        # @return [Boolean] True if the domain label is valid, false otherwise.
        def valid_label?(part)
          part.length <= MAX_LABEL_LENGTH &&
            part.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/i)
        end
      end

      # Parses the given host into domain parts.
      #
      # @param host [String] The host to parse.
      # @return [Parts] The parsed domain parts.
      def self.parse(host)
        Parts.new(host.split('.'))
      end
    end
  end


  # Represents the state of a domain after processing.
  #
  # @attr_reader value [Symbol] The state of the domain.
  # @attr_reader host [String, nil] The normalized host if applicable.
  class State
    attr_reader :value, :host

    # Initializes a new State object.
    #
    # @param value [Symbol] The state of the domain.
    # @param host [String, nil] The normalized host if applicable.
    def initialize(value, host = nil)
      @value = value
      @host = host
    end

    # Checks if the domain state is canonical.
    #
    # @return [Boolean] True if the domain state is canonical, false otherwise.
    def canonical?; value == STATES[:canonical]; end

    # Checks if the domain state is a subdomain.
    #
    # @return [Boolean] True if the domain state is a subdomain, false otherwise.
    def subdomain?; value == STATES[:subdomain]; end

    # Checks if the domain state is custom.
    #
    # @return [Boolean] True if the domain state is custom, false otherwise.
    def custom?; value == STATES[:custom]; end

    # Checks if the domain state is invalid.
    #
    # @return [Boolean] True if the domain state is invalid, false otherwise.
    def invalid?; value == STATES[:invalid]; end
  end

end
